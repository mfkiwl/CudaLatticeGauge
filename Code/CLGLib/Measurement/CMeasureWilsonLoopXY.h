//=============================================================================
// FILENAME : CMeasureWilsonLoopXY.h
// 
// DESCRIPTION:
// This is measurement for Polyakov loop and static quark potential
// Suitable for translational invarient case
//
// REVISION:
//  [09/24/2021 nbale]
//=============================================================================

#ifndef _CMEASUREWILSONLOOPXY_H_
#define _CMEASUREWILSONLOOPXY_H_

__BEGIN_NAMESPACE


__CLG_REGISTER_HELPER_HEADER(CMeasureWilsonLoopXY)

class CLGAPI CMeasureWilsonLoopXY : public CMeasure
{
    __CLGDECLARE_CLASS(CMeasureWilsonLoopXY)

public:

    CMeasureWilsonLoopXY()
        : CMeasure()
        , m_pTmpLoop(NULL)

        , m_pCorrelator(NULL)
        , m_pCorrelatorCounter(NULL)
        , m_pHostCorrelator(NULL)
        , m_pHostCorrelatorCounter(NULL)
        , m_uiMaxLengthSq(1)

        , m_uiConfigurationCount(0)
        , m_bShowResult(FALSE)
    {
    }

    ~CMeasureWilsonLoopXY();

    void Initial(class CMeasurementManager* pOwner, class CLatticeData* pLatticeData, const CParameters&, BYTE byId) override;
    void OnConfigurationAccepted(const class CFieldGauge* pAcceptGauge, const class CFieldGauge* pCorrespondingStaple) override;
    void SourceSanning(const class CFieldGauge* pAcceptGauge, const class CFieldGauge* pCorrespondingStaple, const TArray<CFieldFermion*>& sources, const SSmallInt4& site) override {}
    void Average(UINT uiConfigurationCount) override;
    void Report() override;
    void Reset() override;

    UBOOL IsGaugeMeasurement() const override { return TRUE; }
    UBOOL IsSourceScanning() const override { return FALSE; }

protected:

    deviceSU3* m_pTmpLoop;

    CLGComplex* m_pCorrelator;
    UINT* m_pCorrelatorCounter;
    CLGComplex* m_pHostCorrelator;
    UINT* m_pHostCorrelatorCounter;

    UINT m_uiMaxLengthSq;

    UINT m_uiConfigurationCount;
    UBOOL m_bShowResult;

public:

    TArray<UINT> m_lstR;
    //m_lstC[conf][r][t]
    TArray<TArray<TArray<CLGComplex>>> m_lstC;
    TArray<TArray<CLGComplex>> m_lstAverageC;
};

__END_NAMESPACE

#endif //#ifndef _CMEASUREWILSONLOOPXY_H_

//=============================================================================
// END OF FILE
//=============================================================================