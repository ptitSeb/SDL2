/*
 * (C) Gražvydas "notaz" Ignotas, 2011,2012
 *
 * This work is licensed under the terms of any of these licenses
 * (at your option):
 *  - GNU GPL, version 2 or later.
 *  - GNU LGPL, version 2.1 or later.
 * See the COPYING file in the top-level directory.
 */

.text
.align 2

#define func(name) \
    .global name; \
    name

@ void *dst, const void *src, int count, uint abits
.macro do_argb bgr2rgb
    vdup.i8    d0, r3
0:
    cmp        r2, #8
    pld        [r1, #64*2]
    blt        3f
1:
    vld4.8     {d4-d7}, [r1]!
2:
.if \bgr2rgb
    vswp       d4, d6		@ BGR->RGB
.endif
    vmov.i8    d7, d0
    subs       r2, r2, #8
    blt        do_argb_finish
    vst4.8     {d4-d7}, [r0]!
    bxeq       lr
    nop
    b          0b

3:
    @ unaligned ending nastiness :(
    add        r12, r1, #8*4
    lsr        r12, #12
    cmp        r12, r1, lsr #12 @ crossing page?
    beq        1b               @ nope, overreading is safe

    @ _wb_'s bad luck, do some slow stuff here
    push       {r0-r2,lr}
    sub        sp, #8*4
    mov        r0, sp
    lsl        r2, #2
    bl         memcpy
    vld4.8     {d4-d7}, [sp]!
    pop        {r0-r2,lr}
    b          2b
.endm

@ void *dst, const void *src, int count, uint global_alpha
.macro do_argb_alpha bgr2rgb global_alpha
    mov        r12, #0xff
.if \global_alpha
    vdup.16    q11, r3
.endif
    vdup.i16   q12, r12

0:
    cmp        r2, #8
    blt        3f
1:
    vld4.8     {d4-d7}, [r1]!
    pld        [r1, #64*2]
    vld4.8     {d0-d3}, [r0]
    pld        [r0, #64+32]
2:
.if \bgr2rgb
    vswp       d4, d6		@ BGR->RGB
.endif
.if !\global_alpha
    vmovl.u8   q11, d7
.endif
    @ d = (((s-d)*a+255)>>8)+d
    vsubl.u8   q8, d4, d0
    vsubl.u8   q9, d5, d1
    vsubl.u8   q10,d6, d2
    vmul.s16   q8, q8, q11
    vmul.s16   q9, q9, q11
    vmul.s16   q10,q10,q11
    vaddhn.i16 d4, q8, q12
    vaddhn.i16 d5, q9, q12
    vaddhn.i16 d6, q10,q12
    vadd.i8    q2, q0
    vadd.i8    d6, d2
    vmov.i8    d7, d3
    subs       r2, r2, #8
    blt        do_argb_finish
    vst4.8     {d4-d7}, [r0]!
    bxeq       lr
    nop
    b          0b

3:
    @ unaligned ending nastiness :(
    add        r3,  r0, #8*4
    add        r12, r1, #8*4
    lsr        r3,  #12
    lsr        r12, #12
    cmp        r3,  r0, lsr #12 @ are we crossing
    cmpeq      r12, r1, lsr #12 @ the page boundary?
    beq        1b               @ nope, overreading is safe

    @ _wb_'s bad luck, do some slow stuff here
    push       {r0-r2, lr}
    vpush      {q11, q12}
    sub        sp, #8*4*2
    lsl        r2, #2
    mov        r1, r0
    mov        r0, sp
    bl         memcpy
    ldr        r2, [sp, #8*4*2 + 16*2 + 8] @ stacked r2
    add        r0, sp, #8*4
    ldr        r1, [sp, #8*4*2 + 16*2 + 4]
    lsl        r2, #2
    bl         memcpy
    vld4.8     {d0-d3}, [sp]!
    vld4.8     {d4-d7}, [sp]!
    vpop       {q11, q12}
    pop        {r0-r2, lr}
    b          2b
.endm


do_argb_finish:
    add        r2, r2, #8
    vzip.8     d4, d5		@ RRR..|GGG.. -> RGRG..
    vzip.8     d6, d7		@ BBB..|000.. -> B0B0..
    vzip.16    q2, q3
              
    vst1.32    d4[0], [r0]!
    cmp        r2, #1
    bxle       lr
    vst1.32    d4[1], [r0]!
    cmp        r2, #2
    bxle       lr
    vst1.32    d5[0], [r0]!
    cmp        r2, #3
    bxle       lr
    vst1.32    d5[1], [r0]!
    cmp        r2, #4
    bxle       lr
    vst1.32    d6[0], [r0]!
    cmp        r2, #5
    bxle       lr
    vst1.32    d6[1], [r0]!
    cmp        r2, #6
    bxle       lr
    vst1.32    d7[0], [r0]!
    bx         lr


@ void *dst, const void *src, int count, uint global_alpha
.macro do_argb_to_rgb565_alpha bgr2rgb global_alpha
    mov        r12, #0xff
.if \global_alpha
    vdup.16    q11, r3
.endif
    vdup.i16   q12, r12
0:
    cmp        r2, #8
    blt        3f
1:
    vld4.8     {d4-d7}, [r1]!
    pld        [r1, #64*2]
    vld2.8     {d1-d2}, [r0]
    pld        [r0, #64+32]
.if \bgr2rgb
    vswp       d4, d6		@ BGR->RGB
.endif
.if !\global_alpha
    vmovl.u8   q11, d7
.endif
    vshl.i8    d0, d1, #3
    vshr.u8    d1, d1, #3
    vsri.i8    d0, d0, #5       @ B
    vsli.i8    d1, d2, #5
    vsri.i8    d2, d2, #5       @ R
    vsri.i8    d1, d1, #6       @ G
    @ d = (((s-d)*a+255)>>8)+d
    vsubl.u8   q8, d4, d0
    vsubl.u8   q9, d5, d1
    vsubl.u8   q10,d6, d2
    vmul.s16   q8, q8, q11
    vmul.s16   q9, q9, q11
    vmul.s16   q10,q10,q11
    vaddhn.i16 d4, q8, q12
    vaddhn.i16 d5, q9, q12
    vaddhn.i16 d6, q10,q12
    vadd.i8    q2, q0
    vadd.i8    d2, d6           @ rrrr rrrr
    vshr.u8    d0, d5, #2
    vshr.u8    d1, d4, #3       @ 000b bbbb
    vsri.i8    d2, d5, #5       @ rrrr rggg
    vsli.i8    d1, d0, #5       @ gggb bbbb
    subs       r2, r2, #8
    blt        do_rgb565_finish
    vst2.8     {d1-d2}, [r0]!
    bxeq       lr
    nop
    b          0b

3:
    @ unaligned ending nastiness :(
    add        r3,  r0, #8*2
    add        r12, r1, #8*4
    lsr        r3,  #12
    lsr        r12, #12
    cmp        r3,  r0, lsr #12 @ are we crossing
    cmpeq      r12, r1, lsr #12 @ the page boundary?
    beq        1b               @ nope, overreading is safe

    nop
    bx         lr               @ abandon ship! (until someone complains)
.endm


do_rgb565_finish:
    vzip.8     d1, d2
    add        r2, r2, #8

    vst1.16    d1[0], [r0]!
    cmp        r2, #1
    bxle       lr
    vst1.16    d1[1], [r0]!
    cmp        r2, #2
    bxle       lr
    vst1.16    d1[2], [r0]!
    cmp        r2, #3
    bxle       lr
    vst1.16    d1[3], [r0]!
    cmp        r2, #4
    bxle       lr
    vst1.16    d2[0], [r0]!
    cmp        r2, #5
    bxle       lr
    vst1.16    d2[1], [r0]!
    cmp        r2, #6
    bxle       lr
    vst1.16    d2[2], [r0]!
    bx         lr


func(neon_ARGBtoXRGB):
    do_argb 0

func(neon_ABGRtoXRGB):
    do_argb 1

func(neon_ARGBtoXRGBalpha):
    do_argb_alpha 0, 0

func(neon_ABGRtoXRGBalpha):
    do_argb_alpha 1, 0

func(neon_ARGBtoXRGBalphaS):
    do_argb_alpha 0, 1

func(neon_ABGRtoXRGBalphaS):
    do_argb_alpha 1, 1

func(neon_ARGBtoRGB565alpha):
    do_argb_to_rgb565_alpha 0, 0

func(neon_ABGRtoRGB565alpha):
    do_argb_to_rgb565_alpha 1, 0

@ vim:filetype=armasm
