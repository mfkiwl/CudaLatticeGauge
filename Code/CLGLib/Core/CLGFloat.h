//=============================================================================
// FILENAME : CLGFloat.h
// 
// DESCRIPTION:
// Add precsion for floats
//
// REVISION:
//  [12/15/2018 nbale]
//=============================================================================
#pragma once

#ifndef _CLGFLOAT_H_
#define _CLGFLOAT_H_

#if _CLG_DOUBLEFLOAT

#define _sqrt sqrt
#define _log log
#define _exp exp
#define _pow pow
#define _sin sin
#define _cos cos
#define __div(a, b) ((a) / (b))
#define __rcp(a) (F(1.0) / (a))
#define _hostlog log
#define _hostlog10 log10
#define _hostexp exp
#define _hostsqrt sqrt

#define _atan2 atan2
#define _make_cuComplex make_cuDoubleComplex
#define _cuCaddf cuCadd
#define _cuCmulf cuCmul
#define _cuCsubf cuCsub
#define _cuConjf cuConj
#define _cuCrealf cuCreal
#define _cuCimagf cuCimag
#define _cuCabsf cuCimag
#define _cuCdivf cuCdiv
#define F(v) v

#else

#if defined(__cplusplus) && defined(__CUDACC__)
#define _sqrt __fsqrt_rn
#define _log __logf
#define _exp __expf
#define _pow __powf
#define _sin __sinf
#define _cos __cosf
#define __div __fdividef
#define __rcp __frcp_rn
#else
//the __function is Intrinsic Functions which can be only used in device
#define _sqrt sqrtf
#define _log logf
#define _exp expf
#define _pow powf
#define _sin sinf
#define _cos cosf
#define __div(a, b) ((a) / (b))
#define __rcp(a) (F(1.0) / (a))
#endif

#define _hostlog logf
#define _hostlog10 log10f
#define _hostexp expf
#define _hostsqrt sqrtf

#define _atan2 atan2f
#define _make_cuComplex make_cuComplex
#define _cuCaddf cuCaddf
#define _cuCmulf cuCmulf
#define _cuCsubf cuCsubf
#define _cuConjf cuConjf
#define _cuCrealf cuCrealf
#define _cuCimagf cuCimagf
#define _cuCabsf cuCabsf
#define _cuCdivf cuCdivf
#define F(v) v##f

#endif

//They are not defined in GCC, so we define them explicitly
#define _CLG_FLT_MIN_ 1E-22F   //When smaller than this, sqrt, divide is very bad

#define _CLG_FLT_DECIMAL_DIG  9                       // # of decimal digits of rounding precision
#define _CLG_FLT_DIG          6                       // # of decimal digits of precision
#define _CLG_FLT_EPSILON      1.192092896e-07F        // smallest such that 1.0+FLT_EPSILON != 1.0
#define _CLG_FLT_HAS_SUBNORM  1                       // type does support subnormal numbers
#define _CLG_FLT_GUARD        0
#define _CLG_FLT_MANT_DIG     24                      // # of bits in mantissa
#define _CLG_FLT_MAX          3.402823466e+38F        // max value
#define _CLG_FLT_MAX_10_EXP   38                      // max decimal exponent
#define _CLG_FLT_MAX_EXP      128                     // max binary exponent
#define _CLG_FLT_MIN          1.175494351e-38F        // min normalized positive value
#define _CLG_FLT_MIN_10_EXP   (-37)                   // min decimal exponent
#define _CLG_FLT_MIN_EXP      (-125)                  // min binary exponent
#define _CLG_FLT_NORMALIZE    0
#define _CLG_FLT_RADIX        2                       // exponent radix
#define _CLG_FLT_TRUE_MIN     1.401298464e-45F        // min positive value


//Those are constants we are using

//save some constant memory of cuda?
#define PI (F(3.141592653589))
// - 1/4294967296UL
#define AM (F(0.00000000023283064365386963))
// - _sqrt(2)
#define SQRT2 (F(1.4142135623730951))
// - 1 / _sqrt(2), or _sqrt(2)/2
#define InvSqrt2 (F(0.7071067811865475))
// - 2.0f * PI
#define PI2 (F(6.283185307179586))

// 1.0f / _sqrt(3)
#define InvSqrt3 (F(0.5773502691896258))
// 2.0f / _sqrt(3)
#define InvSqrt3_2 (F(1.1547005383792517))

#define OneOver6 (F(0.16666666666666666666666666666667))
#define OneOver24 (F(0.04166666666666666666666666666667))

//typically, 0.3-0.5 - arXiv:002.4232
#define OmelyanLambda2 (F(0.38636665500756728))

__BEGIN_NAMESPACE

//NOTE, _Complex is already a keyword in GCC
#if _CLG_DOUBLEFLOAT

typedef double Real;
typedef cuDoubleComplex CLGComplex;

#else

typedef float Real;
typedef cuComplex CLGComplex;

#endif

__END_NAMESPACE

#endif//#ifndef _CLGFLOAT_H_

//=============================================================================
// END OF FILE
//=============================================================================