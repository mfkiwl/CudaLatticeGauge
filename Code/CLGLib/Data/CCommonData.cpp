//=============================================================================
// FILENAME : CCommonData.cpp
// 
// DESCRIPTION:
// This is the class for the common data
//
// REVISION:
//  [12/4/2018 nbale]
//=============================================================================
#include "CLGLib_Private.h"

__BEGIN_NAMESPACE


UINT CCommonData::m_uiDim = 4;
UINT CCommonData::m_uiDir = 4;
UINT CCommonData::m_uiLatticeLength[CCommonData::kMaxDim];
UINT CCommonData::m_uiMaxThread = 1024;
EFieldType CCommonData::m_eGaugeType;

//related with a
//related with beta
FLOAT CCommonData::m_fG = 1.0f;

__END_NAMESPACE

//=============================================================================
// END OF FILE
//=============================================================================