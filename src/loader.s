use64


; Expecting
; - RCX: LoadLibraryA
; - RDX: GetProcAddress
; - R8: lpDllPath
; - R9: lpEntryPoint
_greet:
    ; [0-32[     : for stack alignment
    ; [32]       : for LoadLibraryA
    ; [40]       : for GetProcAddress
    ; [48]       : for lpDllPath
    ; [56]       : for lpEntryPoint
    sub rsp, 8*9

    LoadLibraryA   = 8*4 ; 32
    GetProcAddress = 8*5 ; 40
    lpDllPath      = 8*6 ; 48
    lpEntryPoint   = 8*7 ; 56
    
    mov [rsp + LoadLibraryA], rcx   ; Save LoadLibraryA
    mov [rsp + GetProcAddress], rdx ; Save GetProcAddress
    mov [rsp + lpDllPath], r8        ; Save lpDllPath
    mov [rsp + lpEntryPoint], r9     ; Save lpEntryPoint

    ; Load dll from lpDllPath
    mov rcx, [rsp + lpDllPath]     ; lpDllPath
    mov rax, [rsp + LoadLibraryA]  ; LoadLibraryA
    call rax
    test rax, rax
    jz bad_module_load ; If failed to load user32.dll, exit early

    ; Get address of lpEntryPoint
    mov rcx, rax                    ; hModule
    mov rdx, [rsp + lpEntryPoint]   ; lpProcName
    mov rax, [rsp + GetProcAddress] ; GetProcAddress
    call rax                        ; call GetProcAddress
    test rax, rax
    jz bad_proc_load ; If failed to get lpEntryPoint address, exit early

    ; Call lpEntryPoint    
    ; todo - we should pass pointer to the arguments struct here
    call rax ; call lpEntryPoint

    mov rax, 0 ; exit code 0
    jmp done
bad_module_load:
    mov rax, 1 ; exit code 1 for module load failure
    jmp done
bad_proc_load:
    mov rax, 2 ; exit code 2 for proc load failure
done:
    add rsp, 8*9 ; Restore stack
    ret
