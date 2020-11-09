//=============================================================================
// FILENAME : CFieldFermionKSSU3R.h
// 
// DESCRIPTION:
// This is the class for Kogut-Susskind staggered fermions
// For pseudo fermion, this is in fact a boson field phi.
//
// Current implementation, assumes square lattice
//
// REVISION:
//  [09/05/2020 nbale]
//=============================================================================

#ifndef _CFIELDFERMIONKSSU3D_H_
#define _CFIELDFERMIONKSSU3D_H_

__BEGIN_NAMESPACE

__CLG_REGISTER_HELPER_HEADER(CFieldFermionKSSU3D)

class CLGAPI CFieldFermionKSSU3D : public CFieldFermionKSSU3
{
    __CLGDECLARE_FIELD(CFieldFermionKSSU3D)

public:

    void DerivateD0(void* pForce, const void* pGaugeBuffer) const override;
    void DOperatorKS(void* pTargetBuffer, const void* pBuffer, const void* pGaugeBuffer, Real fam,
        UBOOL bDagger, EOperatorCoefficientType eOCT, Real fRealCoeff, const CLGComplex& cCmpCoeff) const override;


    void FixBoundary() override;
    void PrepareForHMC(const CFieldGauge* pGauge) override;

    CCString GetInfos(const CCString& tab) const override;

};

__END_NAMESPACE

#endif //#ifndef _CFIELDFERMIONKSSU3R_H_

//=============================================================================
// END OF FILE
//=============================================================================