format PE64 GUI
entry _start

STD_OUTPUT_HANDLE = -11

; func1(int a, int b, int c, int d, int e, int f);
; a in RCX, b in RDX, c in R8, d in R9, f then e passed on stack

section '.text' code readable executable

_start:
    sub rsp, 8*5 ; Stack align    
    
    mov rcx, 0 ; null
    mov rdx, message
    mov r8, caption
    mov r9, 0 ; MB_OK
    call [MessageBoxA] ; show message box with greeting 
    
    mov ecx, 0 ; exit code 0
    call [ExitProcess] ; exit the process


section '.data' data readable writable
    bytes_written dq 0
    message db 'Hello, World!', 0
    msg_len = $ - message
    caption db 'Greeting', 0
    cap_len = $ - caption

section '.idata' import data readable
    dd 0,0,0, RVA kernel_name, RVA kernel_table
    dd 0,0,0, RVA user_name,   RVA user_table
    dd 0,0,0,0,0

kernel_table:
    ExitProcess   dq RVA _ExitProcess
    GetStdHandle  dq RVA _GetStdHandle
    WriteFile     dq RVA _WriteFile
    dq 0

user_table:
    MessageBoxA   dq RVA _MessageBoxA
    dq 0

kernel_name       db 'KERNEL32.DLL',0
user_name         db 'USER32.DLL',0

_ExitProcess      db 0,0,'ExitProcess',0
_GetStdHandle     db 0,0,'GetStdHandle',0
_WriteFile        db 0,0,'WriteFile',0
_MessageBoxA      db 0,0,'MessageBoxA',0

; void ExitProcess(UINT uExitCode);
; DWORD GetStdHandle(DWORD nStdHandle);
; BOOL WriteFile(HANDLE hFile, LPCVOID lpBuffer, DWORD nNumberOfBytesToWrite, LPDWORD lpNumberOfBytesWritten, LPOVERLAPPED lpOverlapped);
; int MessageBoxA(HWND hWnd, LPCSTR lpText, LPCSTR lpCaption, UINT uType);
