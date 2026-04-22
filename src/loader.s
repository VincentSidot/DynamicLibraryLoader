use64

macro save dst, src {
    mov rax, src
    mov dst, rax
}

; Return codes
SUCCESS                      = 0
ERROR_FETCH_KERNEL32         = 1
ERROR_FETCH_GET_PROC_ADDRESS = 2
ERROR_FETCH_LOAD_LIBRARY     = 3
ERROR_FETCH_FREE_LIBRARY     = 4
ERROR_LOAD_LIBRARY           = 5
ERROR_FREE_LIBRARY           = 6
ERROR_GET_PROC_ADDRESS       = 7
ERROR_NULL_DLL_PATH          = 8
ERROR_NULL_ENTRY_POINT       = 9
ERROR_NULL_LOADER            = 10

; typdef struct {
;     const char* dllPath;
;     const char* entryPoint;
;     void* args;
; } s_Args ;

; Expecting
; - RCX: *const s_Args
; - Clobbers: RAX, RCX, RDX, R8, R9, R10, R11, flags (all volatile registers)
_start:
    ; [0-32[     : for stack alignment
    ; [32]       : for Handle
    ; [40]       : for LoadLibraryA
    ; [48]       : for FreeLibrary
    ; [56]       : for GetProcAddress
    ; [64]       : for lpDllPath
    ; [72]       : for lpEntryPoint
    ; [80]       : for lpArgs (optional)
    StackAllocationSize = 8*11 ; 88 bytes for stack variables
    sub rsp, StackAllocationSize ; Allocate stack space for local variables


    ; Define offsets for the stack variables
    Handle         = 8*4  ; 32
    LoadLibraryA   = 8*5  ; 40
    FreeLibrary    = 8*6  ; 48
    GetProcAddress = 8*7  ; 56
    lpDllPath      = 8*8  ; 64
    lpEntryPoint   = 8*9  ; 72
    lpArgs         = 8*10 ; 80

    test rcx, rcx
    jz .bad_NullLoader

    ; Save the arguments from the s_Args struct
    save [rsp + lpDllPath],      [rcx]        ; Save lpDllPath
    test rax, rax
    jz .bad_NullDllPath
    save [rsp + lpEntryPoint],   [rcx + 0x08] ; Save lpEntryPoint
    test rax, rax
    jz .bad_NullEntryPoint
    save [rsp + lpArgs],         [rcx + 0x10] ; Save lpArgs

    ; Load & Save kernel32.dll base address    
    lea rcx, [_Kernel]          ; Load pointer to "kernel32.dll" string into rcx
    call find_handle
    test rax, rax
    jz .bad_FetchKernel32
    mov [rsp + Handle], rax ; Save kernel32.dll base address

    ; Load & Save the function pointers
    mov rcx, rax                   ; Handle
    lea rdx, [_GetProcAddress]     ; Load "GetProcAddress" string
    call find_export
    test rax, rax
    jz .bad_FetchGetProcAddress
    mov [rsp + GetProcAddress], rax ; Save GetProcAddress address

    mov rcx, [rsp + Handle]       ; Handle
    lea rdx, [_LoadLibraryA]      ; Load "LoadLibraryA" string
    call find_export
    test rax, rax
    jz .bad_FetchLoadLibrary
    mov [rsp + LoadLibraryA], rax ; Save LoadLibraryA address

    mov rcx, [rsp + Handle]       ; Handle
    lea rdx, [_FreeLibrary]       ; Load "FreeLibrary" string
    call find_export
    test rax, rax
    jz .bad_FetchFreeLibrary
    mov [rsp + FreeLibrary], rax ; Save FreeLibrary address
    
    ; Load dll from lpDllPath
    mov rcx, [rsp + lpDllPath]     ; lpDllPath
    mov rax, [rsp + LoadLibraryA]  ; LoadLibraryA
    call rax
    test rax, rax
    jz .bad_LoadLibraryA

    mov [rsp + Handle], rax ; Save hModule for later FreeLibrary call

    ; Get address of lpEntryPoint
    mov rcx, rax                    ; hModule
    mov rdx, [rsp + lpEntryPoint]   ; lpProcName
    mov rax, [rsp + GetProcAddress] ; GetProcAddress
    call rax                        ; call GetProcAddress
    test rax, rax
    jz .bad_GetProcAddress

    ; Call lpEntryPoint    
    mov rcx, [rsp + lpArgs]     ; lpArgs (optional, can be null)
    call rax ; call lpEntryPoint
    xor rax, rax ; Ignore return value of entry point

.free_library:
    mov [rsp + GetProcAddress], rax ; Save rax
    ; Free the loaded module
    mov rcx, [rsp + Handle]         ; hModule
    mov rax, [rsp + FreeLibrary]    ; FreeLibrary
    call rax
    test rax, rax
    jz .bad_FreeLibrary
    
    mov rax, [rsp + GetProcAddress] ; ErrorFlag
    jmp .done ; If ErrorFlag is set, skip setting exit code to 0 and exit with
              ; error

.bad_FetchKernel32:
    mov rax, ERROR_FETCH_KERNEL32
    jmp .done
.bad_FetchGetProcAddress:
    mov rax, ERROR_FETCH_GET_PROC_ADDRESS
    jmp .done
.bad_FetchLoadLibrary:
    mov rax, ERROR_FETCH_LOAD_LIBRARY
    jmp .done
.bad_FetchFreeLibrary:
    mov rax, ERROR_FETCH_FREE_LIBRARY
    jmp .done
.bad_LoadLibraryA:
    mov rax, ERROR_LOAD_LIBRARY
    jmp .done
.bad_GetProcAddress:
    mov rax, ERROR_GET_PROC_ADDRESS
    jmp .free_library ; Attempt to free the module if proc load failed
.bad_NullDllPath:
    mov rax, ERROR_NULL_DLL_PATH
    jmp .done
.bad_NullEntryPoint:
    mov rax, ERROR_NULL_ENTRY_POINT
    jmp .done
.bad_NullLoader:
    mov rax, ERROR_NULL_LOADER
    jmp .done
.bad_FreeLibrary:
    mov rax, ERROR_FREE_LIBRARY
.done:
    add rsp, StackAllocationSize ; Restore stack
    ret

; Loading function.

; typedef struct _PEB {
;   BYTE                          Reserved1[2];
;   BYTE                          BeingDebugged;
;   BYTE                          Reserved2[1];
;   // 4 bytes padding here for alignment
;   PVOID                         Reserved3[2];
;   PPEB_LDR_DATA                 Ldr;                                      0x18
;   ...
; } PEB, *PPEB;

; typedef struct _PEB_LDR_DATA {
;     BYTE                        Reserved1[8];
;     PVOID                       Reserved2[3];
;     LIST_ENTRY                  InMemoryOrderModuleList;                  0x20
; } PEB_LDR_DATA, *PPEB_LDR_DATA;

; typedef struct _LIST_ENTRY {
;    struct _LIST_ENTRY *Flink;                                             0x00
;    struct _LIST_ENTRY *Blink;                                             0x08
; } LIST_ENTRY, *PLIST_ENTRY, *RESTRICTED_POINTER PRLIST_ENTRY;

; typedef struct _LDR_DATA_TABLE_ENTRY {
;     PVOID Reserved1[2];
;     LIST_ENTRY InMemoryOrderLinks;                                        0x10
;     PVOID Reserved2[2];
;     PVOID DllBase;                                                        0x30
;     PVOID Reserved3[2];
;     UNICODE_STRING FullDllName;                                           0x48
;     BYTE Reserved4[8]; // BaseDllName (hidden by microsoft)               0x58 
;     ...
; } LDR_DATA_TABLE_ENTRY, *PLDR_DATA_TABLE_ENTRY;

; This function will be used to find the address of dll in the process's memory
; by traversing the PEB's data structures.
; - RCX: {cstr} target dll name
; - Return value: Address of dll base in RAX, or 0 if not found
; - Clobbers: RAX, RCX, RDX, R8, R9, R10, R11, flags
find_handle:
    ; Reserve space for local variables
    ; [0-32[     : for stack alignment
    ; [32]       ; for list header pointer
    ; [40]       ; for BaseDllName pointer
    ; [48]       ; for DllBase pointer
    ; [56]       ; for target dll name
    
    StackAllocationSize = 8*9 ; 72 bytes for local variables and stack alignment
    sub rsp, StackAllocationSize ; Allocate stack space for local variables

    HeaderOffset      = 8*4 ; 32 bytes for list header pointer
    BaseDllPtrOffset  = 8*5 ; 40 bytes for BaseDllName pointer
    DllBaseAddrOffset = 8*6 ; 48 bytes for DllBase pointer
    TargetDllOffset   = 8*7 ; 56 bytes for target dll name

    test rcx, rcx ; Check if target dll name pointer is null
    jz .not_found ; If target dll name pointer is null, we consider it not found

    mov [rsp + TargetDllOffset], rcx ; Save target dll name pointer

    ; PEB offsets
    LdrOffset                      = 0x18
    
    ; PEB_LDR_DATA offsets
    InMemoryOrderModuleListOffset  = 0x20
    
    ; LIST_ENTRY offsets
    FlinkOffset                    = 0x00
    
    ; LDR_DATA_TABLE_ENTRY offsets
    InMemoryOrderLinksOffset       = 0x10 ; Offset of the linked list pointers
    DllBaseOffset                  = 0x30 
    FullDllNameOffset              = 0x48 
    BaseDllNameOffset              = 0x58 

    ; r11 will point to the current entry in the InMemoryOrderModuleList in the
    ;                   loop iteration
    ; r10 will point to the current DllBase in the loop
    ; rcx will point to the current BaseDllName in the loop

    mov r11, [gs:0x60]                             ; Get PEB address
    mov r11, [r11 + LdrOffset]                     ; Get PEB_LDR_DATA
    lea r11, [r11 + InMemoryOrderModuleListOffset] ; list head

    mov [rsp + HeaderOffset], r11 ; Save list header pointer for loop
                                  ; termination check

    ; Loop through InMemoryOrderModuleList to find target dll
.find_target_handle:
    mov r11, [r11 + FlinkOffset] ; Move to next entry in the list

    cmp r11, [rsp + HeaderOffset] ; Check if we've looped back to the start of
                                  ; the list
    jz .not_found ; If we looped back to the start, dll was not found

    mov r10,  [r11 + DllBaseOffset     - InMemoryOrderLinksOffset] ; DllBase
    lea rcx,  [r11 + BaseDllNameOffset - InMemoryOrderLinksOffset] ; BaseDllName

    mov [rsp + BaseDllPtrOffset], rcx  ; Save BaseDllName pointer for istreq
    mov [rsp + DllBaseAddrOffset], r10 ; Save DllBase address for istreq
    mov rdx, [rsp + TargetDllOffset]   ; Load target dll name pointer for istreq

    call istreq        ; Compare BaseDllName with target dll name (rcx)

    mov r10, [rsp + DllBaseAddrOffset] ; Restore DllBase pointer after istreq    
    
    test rax, rax
    jz .found_target ; If match found, jump to found_target
    
    jmp .find_target_handle

.found_target:
    ; r10 contains the DllBase of the target dll, which we can use to find
    ; GetProcAddress
    mov rax, r10 ; Save target dll base address in rax for GetProcAddress search
    jmp .done
.not_found:
    xor rax, rax ; Return 0 if dll was not found
.done:
    add rsp, StackAllocationSize ; Restore stack
    ret

; typedef struct _UNICODE_STRING {
;     USHORT Length;                                             Length in bytes
;     USHORT MaximumLength;                                               Unused
;     PWSTR  Buffer;                                               UTF-16 buffer
; } UNICODE_STRING;

; String equal function to compare a UNICODE_STRING with a null-terminated ASCII
; string. The comparison is case-insensitive and only considers ASCII characters.
; Any non-ASCII characters in the UNICODE_STRING will cause the function to
; return non-zero (not equal).
; - RCX: pointer to first string  (UNICODE_STRING)
; - RDX: pointer to second string (null-terminated ASCII string)
; - Return value: 0 if strings are equal (case-insensitive), non-zero otherwise
; clobber: RAX, RCX, RDX, R8, R9, R10, flags
istreq:
    ; r9  will store loop index
    ; r10 will store string length in 16-bit characters (not bytes)

    test rdx, rdx ; Check if ascii string pointer is null
    jz .not_equal ; If ascii string pointer is null, we consider it not equal
    test rcx, rcx ; Check if unicode string pointer is null
    jz .not_equal ; If unicode string pointer is null, we consider it not equal

    xor r9, r9 ; Clear r9 for loop index

    xor r10, r10    ; Clear r10 for string length calculation
    mov r10w, [rcx] ; Load Length from UNICODE_STRING (2 bytes)
    shr r10w, 1     ; Convert length from bytes to character count (divide by 2)
                    ; This is safe because UNICODE_STRING Length should always
                    ; be even (UTF-16 characters)

    mov rcx, [rcx + 0x08] ; Load Buffer pointer from UNICODE_STRING
.loop:
    mov r8b, [rdx] ; Load 1 byte from ascii string

    ; Check if we've reached the end of UNICODE_STRING
    cmp r9, r10 ; Compare with string length
    jae .check_ascii_end ; If we've reached the end of the unicode string, check
                         ; if the ascii string also ends here for a match

    mov ax,  [rcx] ; Load 2 bytes from unicode string

    ; Ensure unicode upper byte is 0 (ASCII character)
    test ah, ah
    jnz .not_equal ; If upper byte is not 0, it's not a valid ASCII character

    ; Convert to uppercase if lowercase (ASCII only)
    cmp al, 'a'
    jb .check_second
    cmp al, 'z'
    ja .check_second
    and al, 0xDF ; Convert to uppercase (clear bit 5)
.check_second:
    cmp r8b, 'a'
    jb .compare
    cmp r8b, 'z'
    ja .compare
    and r8b, 0xDF ; Convert to uppercase (clear bit 5)
.compare:
    cmp al, r8b
    jne .not_equal
    test r8b, r8b ; Check for null terminator
    jz .not_equal ; If ascii string ends before unicode string, they are not
                  ; equal

    add rcx, 2 ; Move to next character in unicode string    
    inc rdx
    inc r9 ; Increment loop index
    jmp .loop

.check_ascii_end:
    ; Check if ascii string also ends here (null terminator)
    test r8b, r8b
    jz .equal ; Both strings ended at the same length, they are equal
.not_equal:
    mov rax, 1 ; Strings are not equal
    ret
.equal:
    xor rax, rax ; Strings are equal, return 0
    ret


; This function will be used to find the address of an exported function in a
; dll by parsing the PE headers and export directory.
; - RCX: {handle} Base address of dll in memory
; - RDX: {cstr}   Name of the exported function to find
; - Return value: Address of the exported function in RAX, or 0 if not found
; - Clobbers: RAX, RCX, RDX, R8, R9, R10, R11, flags (all volatile registers)
find_export:
    ; Reserve space for local variables
    ; [0-32[     : shadow space
    ; [32]       ; for handle base address
    ; [40]       ; for names array
    ; [48]       ; for IMAGE_EXPORT_DIRECTORY
    ; [56]       ; for loop index

    StackAllocationSize = 8*9 ; 72 bytes for local variables and stack alignment
    sub rsp, StackAllocationSize ; Allocate stack space for local variables

    HandleOffset     = 8*4 ; 32 bytes for dll handle base address
    NamesArrayOffset = 8*5 ; 40 bytes for names array pointer
    ExportDirOffset  = 8*6 ; 48 bytes for IMAGE_EXPORT_DIRECTORY
    IndexOffset      = 8*7 ; 56 bytes for loop index

    test rcx, rcx ; Check if dll handle pointer is null
    jz .not_found ; If dll handle pointer is null, we consider it not found
    test rdx, rdx ; Check if export name pointer is null
    jz .not_found ; If export name pointer is null, we consider it not found

    mov [rsp + HandleOffset], rcx ; Save dll handle base address for later use
                                  ; in calculations
    mov r10, rdx                  ; Save export name pointer in r10 for later
                                  ; use in streq

    xor rax, rax
    mov [rsp + IndexOffset], rax  ; index = 0 for loop

    ; NT headers
    mov eax, [rcx + 0x3C] ; e_lfanew
    add rcx, rax          ; rcx = NT headers

    ; Export Directory RVA
    mov eax, [rcx + 0x18 + 0x70]
    test eax, eax
    jz .not_found ; If Export Directory RVA is 0, there are no exports, so we
                  ; consider it not found

    mov r11, [rsp + HandleOffset]    ; module base
    add rax, r11                     ; rax = export dir va
    mov r8, rax                      ; r8 = IMAGE_EXPORT_DIRECTORY
    mov [rsp + ExportDirOffset], rax ; Save IMAGE_EXPORT_DIRECTORY for later
                                     ; use in calculations

    NumberOfNamesOffset         = 0x18 ; Offset of NumberOfNames (DWORD)
    AddressOfFunctionsOffset    = 0x1C ; Offset of AddressOfFunctions RVA
    AddressOfNamesOffset        = 0x20 ; Offset of AddressOfNames RVA
    AddressOfNameOrdinalsOffset = 0x24 ; Offset of AddressOfNameOrdinals RVA

    ; Load NumberOfNames
    mov r9d, [r8 + NumberOfNamesOffset] ; r9d = NumberOfNames
    test r9d, r9d
    jz .not_found ; If NumberOfNames is 0, there are no exports

    ; names array VA
    mov eax, [r8 + AddressOfNamesOffset] ; AddressOfNames RVA
    add rax, r11                         ; rax = names array VA
    mov [rsp + NamesArrayOffset], rax    ; Save names array VA for loop access

.loop:
    mov edx, [rsp + IndexOffset] ; Load current index for loop
    
    cmp edx, r9d
    jae .not_found ; index >= NumbersOfNames, export not found

    mov rcx, [rsp + NamesArrayOffset] ; rcx = names array VA
    mov ecx, [rcx + rdx*4]            ; ecx = name RVA
    add rcx, r11                      ; rcx = name VA

    mov rdx, r10           ; export name to compare

    call streq             ; Compare export name with target export name
                           ; (case-sensitive)

    test rax, rax
    jz .found ; If match found, jump to found

    inc dword [rsp + IndexOffset]       ; index++
    jmp .loop

.found:
    ; rdx contains the index of the export, which we can use to find the
    ; corresponding function RVA and calculate its VA

    mov r8, [rsp + ExportDirOffset] ; Load IMAGE_EXPORT_DIRECTORY for
                                    ; calculations
    mov edx, [rsp + IndexOffset]    ; Load export index for calculations

    ; names ordinals array VA
    mov eax, [r8 + AddressOfNameOrdinalsOffset] ; AddressOfNameOrdinals RVA
    add rax, r11                                ; rax = name ordinals array VA

    movzx edx, word [rax + rdx*2]               ; edx = ordinal index

    ; functions array VA
    mov eax, [r8 + AddressOfFunctionsOffset]    ; AddressOfFunctions RVA
    add rax, r11                                ; rax = functions array VA

    mov eax, [rax + rdx*4]                      ; eax = function RVA
    add rax, r11                                ; rax = function VA

    jmp .done

.not_found:
    xor rax, rax ; If we fail to find the export, we return

.done:
    add rsp, StackAllocationSize ; Restore stack
    ret

; String equal function to compare two null-terminated ASCII strings. The 
; comparison is case-sensitive.
; - RCX: pointer to first string  (null-terminated ASCII string)
; - RDX: pointer to second string (null-terminated ASCII string)
; - Return value: 0 if strings are equal, non-zero otherwise
; clobber: RAX, RCX, RDX, R8, flags
streq:
    test rcx, rcx ; Check if first string pointer is null
    jz .not_equal ; If first string pointer is null, we consider it not equal
    test rdx, rdx ; Check if second string pointer is null
    jz .not_equal ; If second string pointer is null, we consider it not equal

.loop:
    mov al, [rcx] ; Load 1 byte from first string
    mov r8b, [rdx] ; Load 1 byte from second string

    cmp al, r8b
    jne .not_equal ; If characters are not equal, strings are not equal
    test al, al ; Check for null terminator
    jz .equal ; If end of string, strings are equal

    inc rcx
    inc rdx
    jmp .loop

.not_equal:
    mov rax, 1 ; Strings are not equal
    ret
.equal:
    xor rax, rax ; Strings are equal, return 0
    ret

; Data section here
_Kernel            db "kernel32.dll"   , 0
_GetProcAddress    db "GetProcAddress" , 0
_LoadLibraryA      db "LoadLibraryA"   , 0
_FreeLibrary       db "FreeLibrary"    , 0