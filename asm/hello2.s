format pe64 console
entry _start

section '.text' code readable executable

; func1(int a, int b, int c, int d, int e, int f);
; a in RCX, b in RDX, c in R8, d in R9, f then e passed on stack

_start:
    sub rsp, 8*5 ; Stack align

    ; Load user32.dll
    mov rcx, user_name
    call [LoadLibraryA]

    test rax, rax
    jz bad_module_load ; If failed to load user32.dll, exit early

    mov rcx, rax ; hModule
    mov rdx, msg_box_a_name ; lpProcName
    call [GetProcAddress]

    test rax, rax
    jz bad_proc_load ; If failed to get MessageBoxA address, exit early

    mov rcx, 0 ; hWnd
    mov rdx, message ; lpText
    mov r8, caption ; lpCaption
    mov r9, 0 ; uType (MB_OK)
    call rax ; call MessageBoxA

    mov rcx, 0 ; exit code 0
    jmp done

bad_module_load:
    mov rcx, 1 ; exit code 1 for module load failure
    jmp done

bad_proc_load:
    mov rcx, 2 ; exit code 2 for proc load failure
    jmp done

done:
    call [ExitProcess] ; exit the process

section '.data' data readable writable
    msg_box_a_name db 'MessageBoxA',0
    message db 'Hello, World!', 0
    caption db 'Greeting', 0

section '.idata' import data readable
    dd 0,0,0, RVA kernel_name, RVA kernel_table
    dd 0,0,0,0,0

kernel_table:
    ExitProcess      dq RVA _ExitProcess
    GetModuleHandleA dq RVA _GetModuleHandleA
    GetProcAddress   dq RVA _GetProcAddress
    LoadLibraryA     dq RVA _LoadLibraryA
    dq 0

kernel_name      db 'KERNEL32.DLL',0
user_name        db 'USER32.DLL',0

_ExitProcess      db 0,0,'ExitProcess',0
_GetModuleHandleA db 0,0,'GetModuleHandleA',0
_GetProcAddress   db 0,0,'GetProcAddress',0
_LoadLibraryA     db 0,0,'LoadLibraryA',0

; void ExitProcess(UINT uExitCode);
; HMODULE GetModuleHandleA(LPCSTR lpModuleName);
; FARPROC GetProcAddress(HMODULE hModule, LPCSTR lpProcName);
; HMODULE LoadLibraryA(LPCSTR lpLibFileName);