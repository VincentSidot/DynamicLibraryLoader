use64

; Expecting
; - RCX: MessageBoxA
; - RDX: lpText
; - R8: lpCaption
_greet:
    sub rsp, 8*5 ; Stack align

    mov r10, rcx; MessageBoxA

    mov rcx, 0 ; hWnd
    mov r9, 0 ; uType (MB_OK)

    call r10 ; call MessageBoxA

    mov rax, 0 ; exit code 0
    add rsp, 8*5 ; Restore stack
    ret