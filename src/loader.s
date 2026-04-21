use64

; Struct for arguments:

; typedef struct {
;     LoadLibraryFn loadLibraryA;
;     FreeLibraryFn freeLibrary;
;     GetProcAddressFn getProcAddress;
; } s_LoaderFunctions;

; typdef struct {
;     const char* dllPath;
;     const char* entryPoint;
; } s_LoaderPath ;

macro save dst, src {
    mov rax, src
    mov dst, rax
}

; Expecting
; - RCX: *const s_LoaderFunctions
; - RDX: *const s_LoaderPath
; - R8:  *mut   void
_greet:
    ; [0-32[     : for stack alignment
    ; [32]       : for LoadLibraryA
    ; [40]       : for FreeLibrary
    ; [48]       : for GetProcAddress
    ; [56]       : for lpDllPath
    ; [64]       : for lpEntryPoint
    ; [72]       : for lpVoidArgs (optional)
    StackAllocationSize = 8*11 ; 88 bytes for stack variables
    sub rsp, StackAllocationSize ; Allocate stack space for local variables

    ; Define offsets for the stack variables
    LoadLibraryA   = 8*4 ; 32
    FreeLibrary    = 8*5 ; 40
    GetProcAddress = 8*6 ; 48
    lpDllPath      = 8*7 ; 56
    lpEntryPoint   = 8*8 ; 64
    lpVoidArgs     = 8*9 ; 72

    ; Load the function pointers from the s_LoaderFunctions struct
    save [rsp + LoadLibraryA],   [rcx]      ; Save LoadLibraryA / hModule
    save [rsp + FreeLibrary],    [rcx + 8]  ; Save FreeLibrary
    save [rsp + GetProcAddress], [rcx + 16] ; Save GetProcAddress / ErrorFlag

    ; Load the arguments from the s_LoaderPath struct
    save [rsp + lpDllPath],      [rdx]      ; Save lpDllPath
    save [rsp + lpEntryPoint],   [rdx + 8]  ; Save lpEntryPoint
    
    ; Load optional dll arguments if provided
    mov [rsp + lpVoidArgs],     r8          ; Save lpVoidArgs (optional)

    ; Load dll from lpDllPath
    mov rcx, [rsp + lpDllPath]     ; lpDllPath
    mov rax, [rsp + LoadLibraryA]  ; LoadLibraryA
    call rax
    test rax, rax
    jz bad_LoadLibraryA ; If failed to load user32.dll, exit early

    mov [rsp + LoadLibraryA], rax ; Save hModule for later FreeLibrary call

    ; Get address of lpEntryPoint
    mov rcx, rax                    ; hModule
    mov rdx, [rsp + lpEntryPoint]   ; lpProcName
    mov rax, [rsp + GetProcAddress] ; GetProcAddress
    call rax                        ; call GetProcAddress
    test rax, rax
    jz bad_GetProcAddress ; If failed to get lpEntryPoint address, exit early

    ; Call lpEntryPoint    
    mov rcx, [rsp + lpVoidArgs]     ; lpVoidArgs (optional, can be null)
    call rax ; call lpEntryPoint
    xor rax, rax ; Ignore return value of entry point

free_library:
    mov [rsp + GetProcAddress], rax ; Save rax
    ; Free the loaded module
    mov rcx, [rsp + LoadLibraryA]   ; hModule
    mov rax, [rsp + FreeLibrary]    ; FreeLibrary
    call rax
    test rax, rax
    jz bad_FreeLibrary ; If failed to free the module, exit with error
    
    mov rax, [rsp + GetProcAddress] ; ErrorFlag
    jmp done ; If ErrorFlag is set, skip setting exit code to 0 and exit with error
bad_LoadLibraryA:
    mov rax, 1 ; exit code 1 for module load failure
    jmp done
bad_GetProcAddress:
    mov rax, 2 ; exit code 2 for proc load failure
    jmp free_library ; Attempt to free the module if proc load failed
bad_FreeLibrary:
    mov rax, 3 ; exit code 3 for FreeLibrary failure
done:
    add rsp, StackAllocationSize ; Restore stack
    ret
