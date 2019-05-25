//=============================================================================
// FILENAME : TestRotation.cpp
// 
// DESCRIPTION:
//
// REVISION:
//  [05/10/2019 nbale]
//=============================================================================

#include "CLGTest.h"

UINT TestRotation(CParameters& sParam)
{
    Real fExpected = F(0.65);
    //sParam.FetchValueReal(_T("ExpectedRes"), fExpected);

    //we calculate staple energy from beta = 1 - 6
    //CActionGaugePlaquette * pAction = dynamic_cast<CActionGaugePlaquette*>(appGetLattice()->GetActionById(1));
    //if (NULL == pAction)
    //{
    //    return 1;
    //}
    CMeasurePlaqutteEnergy* pMeasure = dynamic_cast<CMeasurePlaqutteEnergy*>(appGetLattice()->m_pMeasurements->GetMeasureById(1));
    if (NULL == pMeasure)
    {
        return 1;
    }

    //pAction->SetBeta(F(3.0));

    //Equilibration
#if _CLG_DEBUG
    appGetLattice()->m_pUpdator->Update(2, FALSE);
#else
    appGetLattice()->m_pUpdator->Update(2, FALSE);
#endif

    //Measure
    pMeasure->Reset();
    
#if _CLG_DEBUG
    appGetLattice()->m_pUpdator->SetTestHdiff(TRUE);
    appGetLattice()->m_pUpdator->Update(3, TRUE);
#else
    appGetLattice()->m_pUpdator->Update(3, TRUE);
#endif

    Real fRes = pMeasure->m_fLastRealResult;
    appGeneral(_T("res : expected=%f res=%f "), fExpected, fRes);
    UINT uiError = 0;
#if _CLG_DEBUG
    if (appAbs(fRes - fExpected) > F(0.15))
#else
    if (appAbs(fRes - fExpected) > F(0.02))
#endif
    {
        ++uiError;
    }

    UINT uiAccept = appGetLattice()->m_pUpdator->GetConfigurationCount();
    Real fHDiff = appGetLattice()->m_pUpdator->GetHDiff();
#if _CLG_DEBUG
    appGeneral(_T("accept (%d/5) : expected >= 4. HDiff = %f : expected < 1\n"), uiAccept, appGetLattice()->m_pUpdator->GetHDiff());
#else
    appGeneral(_T("accept (%d/25) : expected >= 23. HDiff = %f : expected < 0.1 (exp(-0.1)=90%%)\n"), uiAccept, appGetLattice()->m_pUpdator->GetHDiff());
#endif

#if _CLG_DEBUG
    if (uiAccept < 4)
#else
    if (uiAccept < 23)
#endif
    {
        ++uiError;
    }

#if _CLG_DEBUG
    if (fHDiff > F(1.0))
#else
    if (fHDiff > F(0.1))
#endif
    {
        ++uiError;
    }

    return uiError;
}

__REGIST_TEST(TestRotation, Updator, TestRotation);


//=============================================================================
// END OF FILE
//=============================================================================