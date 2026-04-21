use64

; This is a raw binary file containing the machine code

; Expecting
; - RCX: LoadLibraryA
; - RDX: GetProcAddress
; - R8: lpText
; - R9: lpCaption
_greet:
    ; [0-32[     : for stack alignment
    ; [32]       : for LoadLibraryA
    ; [40]       : for GetProcAddress
    ; [48]       : for lpText
    ; [56]       : for lpCaption
    sub rsp, 8*9

    LoadLibraryA   = 8*4 ; 32
    GetProcAddress = 8*5 ; 40
    lpText         = 8*6 ; 48
    lpCaption      = 8*7 ; 56

    mov [rsp + LoadLibraryA], rcx   ; Save LoadLibraryA
    mov [rsp + GetProcAddress], rdx ; Save GetProcAddress
    mov [rsp + lpText], r8          ; Save lpText
    mov [rsp + lpCaption], r9       ; Save lpCaption

    ; Load user32.dll
    lea rcx, [user_name]          ; lpLoadLibraryA
    mov rax, [rsp + LoadLibraryA] ; LoadLibraryA
    call rax
    test rax, rax
    jz bad_module_load ; If failed to load user32.dll, exit early

    ; Get MessageBoxA address
    mov rcx, rax                    ; hModule
    lea rdx, [msg_box_a_name]       ; lpProcName
    mov rax, [rsp + GetProcAddress] ; GetProcAddress
    call rax                        ; call GetProcAddress
    test rax, rax
    jz bad_proc_load ; If failed to get MessageBoxA address, exit early

    ; Call MessageBoxA
    mov rcx, 0                      ; hWnd
    mov rdx, [rsp + lpText]         ; lpText
    mov r8, [rsp + lpCaption]       ; lpCaption
    mov r9, 0                       ; uType (MB_OK)
    call rax                        ; call MessageBoxA

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

user_name db 'USER32.DLL',0
msg_box_a_name db 'MessageBoxA',0