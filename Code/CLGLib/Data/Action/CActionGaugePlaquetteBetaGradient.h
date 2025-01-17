//=============================================================================
// FILENAME : CActionGaugePlaquetteGradient.h
// 
// DESCRIPTION:
// This is the class for all fields, gauge, fermion and spin fields are inherent from it
//
// REVISION:
//  [08/15/2022 nbale]
//=============================================================================

#ifndef _CACTIONGAUGEPLAQUETTEBETAGRADIENT_H_
#define _CACTIONGAUGEPLAQUETTEBETAGRADIENT_H_

__BEGIN_NAMESPACE

__CLG_REGISTER_HELPER_HEADER(CActionGaugePlaquetteGradient)

class CLGAPI CActionGaugePlaquetteGradient : public CAction
{
    __CLGDECLARE_CLASS(CActionGaugePlaquetteGradient)
public:
    /**
    * Make sure this is called after lattice and fields are created.
    */
    CActionGaugePlaquetteGradient();

#if !_CLG_DOUBLEFLOAT
    DOUBLE Energy(UBOOL bBeforeEvolution, const class CFieldGauge* pGauge, const class CFieldGauge* pStable = NULL) override;
#else
    Real Energy(UBOOL bBeforeEvolution, const class CFieldGauge* pGauge, const class CFieldGauge* pStable = NULL) override;
#endif
    void Initial(class CLatticeData* pOwner, const CParameters& param, BYTE byId) override;

    UBOOL CalculateForceOnGauge(const class CFieldGauge * pGauge, class CFieldGauge * pForce, class CFieldGauge * pStaple, ESolverPhase ePhase) const override;
    void PrepareForHMC(const CFieldGauge* pGauge, UINT uiUpdateIterate) override;
    void OnFinishTrajectory(UBOOL bAccepted) override;
    CCString GetInfos(const CCString &tab) const override;

#if !_CLG_DOUBLEFLOAT
    void SetBeta(const TArray<DOUBLE>& fBeta);
#else
    void SetBeta(const TArray<Real>& fBetas);
#endif

protected:

#if !_CLG_DOUBLEFLOAT
    DOUBLE* m_pDeviceBetaArray;
    DOUBLE m_fLastEnergy;
    DOUBLE m_fNewEnergy;
    TArray<DOUBLE> m_fBetaArray;
#else
    Real* m_pDeviceBetaArray;
    Real m_fLastEnergy;
    Real m_fNewEnergy;
    TArray<Real> m_fBetaArray;
#endif

    //Not using it
    //UBOOL m_bUsing4PlaqutteEnergy;
    UINT m_uiPlaqutteCount;

#if !_CLG_DOUBLEFLOAT
    DOUBLE CalculatePlaqutteEnergyUseClover(const CFieldGaugeSU3* pGauge) const;
#else
    Real CalculatePlaqutteEnergyUseClover(const CFieldGaugeSU3* pGauge) const;
#endif

    void CalculateForceAndStaple(const CFieldGaugeSU3* pGauge, CFieldGaugeSU3* pForce) const;
};

__END_NAMESPACE

#endif //#ifndef _CACTIONGAUGEPLAQUETTEBETAGRADIENT_H_

//=============================================================================
// END OF FILE
//=============================================================================