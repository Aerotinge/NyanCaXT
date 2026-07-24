	cpu 8086                
    org 0x0100              

; ===========================================================================
; CONFIGURATION
; ===========================================================================
; Loop Point: 7.453 seconds * 8000 Hz = 59624 bytes
LOOP_BYTE_LOW   equ 59624   
LOOP_BYTE_HIGH  equ 0

KEYFRAME_TICK   equ 31600   ; 3.95 seconds * 8000
FRAME_TICK      equ 560     ; 70 ms * 8000

; ===========================================================================
; 1. STARTUP & MEMORY ALLOCATION
; ===========================================================================
main:
    mov ah, 09h
    mov dx, msg_loading
    int 21h

    ; Shrink .COM footprint to 64KB
    mov ah, 4Ah             
    mov bx, 4096            
    mov cx, cs              
    int 21h

    ; Allocate 276 KB RAM (17,300 paragraphs)
    mov ah, 48h             
    mov bx, 17300     
    int 21h
    jnc .mem_ok
    
    mov ah, 09h             
    mov dx, err_mem
    int 21h
    mov ax, 4C01h
    int 21h

.mem_ok:
    mov [audio_seg], ax     
    mov [current_seg], ax   

; ===========================================================================
; 2. DISK LOADER
; ===========================================================================
    mov ax, 3D00h           
    mov dx, filename
    int 21h
    jnc .file_ok
    
    mov ah, 09h             
    mov dx, err_file
    int 21h
    mov ax, 4C01h
    int 21h

.file_ok:
    mov [file_handle], ax
    xor ax, ax
    mov [total_low], ax
    mov [total_high], ax

.read_loop:
    mov ds, cs:[current_seg]
    xor dx, dx              

    mov ah, 3Fh
    mov bx, cs:[file_handle] 
    mov cx, 32768           
    int 21h

    mov bx, cs
    mov ds, bx

    add [total_low], ax
    adc [total_high], 0

    push ax
    mov ah, 02h
    mov dl, '.'
    int 21h
    pop ax

    cmp ax, 32768           
    jne .read_done          

    mov ax, [current_seg]
    add ax, 0x0800
    mov [current_seg], ax
    jmp .read_loop

.read_done:
    mov ah, 3Eh             
    mov bx, [file_handle]
    int 21h

; ===========================================================================
; 3. CGA LOW-RES (160x100x16) INITIALIZATION
; ===========================================================================
.setup_playback:
    mov ax, 0003h
    int 10h

    mov ax, 1003h
    mov bl, 00h
    int 10h

    mov dx, 0x03D4          
    mov al, 0x04            
    out dx, al
    inc dx
    mov al, 0x7F            
    out dx, al
    dec dx
    mov al, 0x06            
    out dx, al
    inc dx
    mov al, 0x64            
    out dx, al
    dec dx
    mov al, 0x07            
    out dx, al
    inc dx
    mov al, 0x70            
    out dx, al
    dec dx
    mov al, 0x09            
    out dx, al
    inc dx
    mov al, 0x01            
    out dx, al

    mov dx, 0x03D8          
    mov al, 0x09            
    out dx, al

    mov ax, 0xB800
    mov es, ax
    mov ax, 0x00DE          
    xor di, di
    mov cx, 8000
    rep stosw

; ===========================================================================
; 4. AUDIO LOOP MATHEMATICS
; ===========================================================================
    mov ax, LOOP_BYTE_HIGH
    mov cl, 12
    shl ax, cl              
    add ax, [audio_seg]
    mov [loop_seg], ax      
    
    mov ax, LOOP_BYTE_LOW
    mov [loop_off], ax      

    mov ax, [total_low]
    sub ax, LOOP_BYTE_LOW
    mov [loop_len_low], ax
    mov ax, [total_high]
    sbb ax, LOOP_BYTE_HIGH
    mov [loop_len_high], ax

    mov ax, [total_low]
    mov [play_low], ax
    mov ax, [total_high]
    mov [play_high], ax

    mov ax, [audio_seg]
    mov [smc_seg + 1], ax
    mov word [smc_off + 1], 0

    mov word [isr_tick], 0
    mov byte [keyframe_drawn], 0
    mov word [last_frame_tick], 0
    mov word [anim_ptr], anim_start

    call start_pwm          

; ===========================================================================
; 5. THE MAIN LOOP (Video Sync Engine)
; ===========================================================================
.video_loop:
    cmp byte [keyframe_drawn], 0
    jne .check_delta

    ; KEYFRAME SYNC
    mov ax, [isr_tick]
    cmp ax, KEYFRAME_TICK
    jb .sleep_cpu           ; Wait until time
    
    call draw_keyframe
    mov byte [keyframe_drawn], 1
    mov [last_frame_tick], ax
    jmp .check_keyboard

.check_delta:
    ; DELTA SYNC
    mov ax, [isr_tick]
    sub ax, [last_frame_tick]
    cmp ax, FRAME_TICK
    jb .sleep_cpu           ; Wait until time
    
    call draw_delta
    add word [last_frame_tick], FRAME_TICK

.check_keyboard:
    mov ah, 01h             
    int 16h                 
    jnz .done
    
.sleep_cpu:
    hlt
    jmp .video_loop

.done:
    call stop_pwm
    mov ax, 0003h
    int 10h
    mov ax, 4C00h           
    int 21h

; ===========================================================================
; 6. VIDEO RENDER ROUTINES 
; ===========================================================================
draw_keyframe:
    push ds
    push es
    push di
    push si
    push cx
    
    mov ax, cs
    mov ds, ax
    mov si, keyframe        
    mov ax, 0xB800
    mov es, ax
    xor di, di              
    mov cx, 8000            
    rep movsw               
    
    pop cx
    pop si
    pop di
    pop es
    pop ds
    ret

draw_delta:
    push ds
    push es
    push di
    push si
    
    mov ax, cs
    mov ds, ax
    mov ax, 0xB800
    mov es, ax
    mov si, [anim_ptr]      

.blit_loop:
    lodsw                   ; Read Offset
    cmp ax, 0xFFFF          
    je .frame_done
    mov di, ax              
    lodsw                   ; Read Pixel Word
    stosw                   ; Blast to VRAM
    jmp .blit_loop

.frame_done:
    lodsw
    cmp si, anim_end        
    jb .save_ptr
    mov si, anim_start      
.save_ptr:
    mov [cs:anim_ptr], si
    
    pop si
    pop di
    pop es
    pop ds
    ret

; ===========================================================================
; 7. DIRECT-FETCH RAW ISR 
; ===========================================================================
pwm_isr:
    push ax
    push ds

smc_seg:
    mov ax, 0x0000          
    mov ds, ax
smc_off:
    mov bx, 0x0000          
    
    mov al, [bx]            
    shr al, 1               
    out 42h, al             
    
    mov al, 20h             
    out 20h, al             
    
    inc bx
    jnz .save_ptr
    
    ; 64 KB Segment Wrap!
    mov ax, ds
    add ax, 0x1000
    mov [cs:smc_seg + 1], ax

.save_ptr:
    mov [cs:smc_off + 1], bx
    inc word [cs:isr_tick]  
    
    sub word [cs:play_low], 1
    sbb word [cs:play_high], 0
    jnc .isr_done
    
    ; Loop Point Reset (Instantaneous, no state needed)
    mov ax, [cs:loop_seg]
    mov [cs:smc_seg + 1], ax
    mov ax, [cs:loop_off]
    mov [cs:smc_off + 1], ax
    
    mov ax, [cs:loop_len_low]
    mov [cs:play_low], ax
    mov ax, [cs:loop_len_high]
    mov [cs:play_high], ax

.isr_done:
    pop ds
    pop ax
    iret

; ===========================================================================
; 8. HARDWARE SUPPORT
; ===========================================================================
PIT_FREQ        equ 1193181
SAMPLE_RATE     equ 8000
PWM_DIVIDER     equ PIT_FREQ / SAMPLE_RATE

old_int8_off    dw 0
old_int8_seg    dw 0

start_pwm:
    push ax
    push es
    cli
    xor ax, ax
    mov es, ax
    mov ax, [es:8*4]
    mov [cs:old_int8_off], ax
    mov ax, [es:8*4+2]
    mov [cs:old_int8_seg], ax
    mov word [es:8*4], pwm_isr
    mov word [es:8*4+2], cs
    mov al, 00110100b       
    out 43h, al
    mov ax, PWM_DIVIDER     
    out 40h, al             
    mov al, ah
    out 40h, al             
    mov al, 10010000b       
    out 43h, al
    in al, 61h
    or al, 03h              
    out 61h, al
    sti
    pop es
    pop ax
    ret

stop_pwm:
    push ax
    push es
    cli
    in al, 61h
    and al, 0FCh            
    out 61h, al
    mov al, 00110110b       
    out 43h, al
    xor al, al              
    out 40h, al             
    out 40h, al             
    xor ax, ax
    mov es, ax
    mov ax, [cs:old_int8_off]
    mov [es:8*4], ax
    mov ax, [cs:old_int8_seg]
    mov [es:8*4+2], ax
    sti
    pop es
    pop ax
    ret

; ===========================================================================
; 9. BSS VARIABLES
; ===========================================================================
section .bss
    file_handle resw 1
    audio_seg   resw 1
    current_seg resw 1
    total_low   resw 1
    total_high  resw 1
    play_low    resw 1
    play_high   resw 1
    loop_seg        resw 1
    loop_off        resw 1
    loop_len_low    resw 1
    loop_len_high   resw 1
    
    isr_tick        resw 1
    last_frame_tick resw 1
    keyframe_drawn  resb 1
    anim_ptr        resw 1

; ===========================================================================
; 10. DATA SEGMENT
; ===========================================================================
section .data
filename    db "NYAN.RAW", 0
msg_loading db "Loading Nyan to RAM $"
err_file    db "Error: NYAN.RAW not found!$"
err_mem     db "Error: Need 340KB free RAM$"

align 2
keyframe:
    incbin "frame00.bin"

anim_start:
    incbin "deltas.bin"
anim_end: