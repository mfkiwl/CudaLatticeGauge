//=============================================================================
// FILENAME : CActionGaugePlaquetteRotating.h
// 
// DESCRIPTION:
// This is the class for rotating guage action
// Open boundary condition (identity Dirichlet boundary condition) is assumed 
// 
//
// REVISION:
//  [05/07/2019 nbale]
//=============================================================================

#ifndef _CACTIONGAUGEPLAQUETTE_ROTATING_H_
#define _CACTIONGAUGEPLAQUETTE_ROTATING_H_

__BEGIN_NAMESPACE

__CLG_REGISTER_HELPER_HEADER(CActionGaugePlaquetteRotating)

class CLGAPI CActionGaugePlaquetteRotating : public CAction
{
    __CLGDECLARE_CLASS(CActionGaugePlaquetteRotating)
public:

    CActionGaugePlaquetteRotating();

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
    void SetBeta(DOUBLE fBeta);
    void SetOmega(DOUBLE fOmega);
#else
    void SetBeta(Real fBeta);
    void SetOmega(Real fOmega);
#endif
    void SetCenter(const SSmallInt4 &newCenter);
    //Real GetEnergyPerPlaqutte() const;

#if !_CLG_DOUBLEFLOAT
    DOUBLE m_fOmega;
#else
    Real m_fOmega;
#endif
    UBOOL m_bCloverEnergy;
    UBOOL m_bShiftHalfCoord;

    //===== test functions ======
    DOUBLE XYTerm1(const class CFieldGauge* pGauge);
    DOUBLE XYTerm2(const class CFieldGauge* pGauge);

protected:

#if !_CLG_DOUBLEFLOAT
    DOUBLE m_fLastEnergy;
    DOUBLE m_fNewEnergy;
    DOUBLE m_fBetaOverN;
#else
    Real m_fLastEnergy;
    Real m_fNewEnergy;
    Real m_fBetaOverN;
#endif

    UINT m_uiPlaqutteCount;
};

//================= Put those device functions to header file because we will use them ==============

#pragma region device function

#pragma region Energy

#pragma region Plaqutte term

/**
* Product of 3 terms
* U(uiBIa)_{byDira} . U(uiBIb)_{byDirb} . U(uiBIc)_{byDirc}
* To calcuate staple
*/
static __device__ __inline__ deviceSU3 _deviceGetSTTerm(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SIndex& linkA, const SIndex& linkB, const SIndex& linkC)
{
    deviceSU3 ret(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, linkA, byFieldId));
    ret.Mul(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, linkB, byFieldId));
    ret.Mul(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, linkC, byFieldId));
    return ret;
}

static __device__ __inline__ Real _device1PlaqutteTermReTr(
    const deviceSU3* __restrict__ pDeviceData, BYTE byFieldId,
    BYTE byMu, BYTE byNu, UINT uiBigIdx, const SSmallInt4& sSite4)
{
    return _device1PlaqutteTermPP(pDeviceData, byMu, byNu, uiBigIdx, sSite4, byFieldId).ReTr();
}

/**
* 3 - 1/4 Retr[ U_{mu,nu}(n)+U_{-mu,nu}(n)+U_{mu,-nu}(n)+U_{-mu,-nu}(n) ]
* = 3 - 1/4 Retr[ U_{mu,nu}(n)+U^+_{mu,nu}(n-mu)+U^+_{mu,nu}(n-nu)+U_{mu,nu}(n-mu-nu) ]
* = 3 - 1/4 Retr[ U_{mu,nu}(n)+U_{mu,nu}(n-mu)+U_{mu,nu}(n-nu)+U_{mu,nu}(n-mu-nu) ]
* Hey! it is wrong but correct!
* In fact, it is
* 3 - 1/4 Retr[ U_{mu,nu}(n)+U^+_{-mu,nu}(n)+U^+_{mu,-nu}(n)+U_{-mu,-nu}(n) ]
* which is 
* 3 - 1/4 Retr[ U_{mu,nu}(n)+U_{mu,nu}(n-mu)+U_{mu,nu}(n-nu)+U_{mu,nu}(n-mu-nu) ]
* Thanks to Retr!
*/
static __device__ __inline__ Real _device4PlaqutteTerm(const deviceSU3* __restrict__ pDeviceData,
    BYTE byMu, BYTE byNu, UINT uiBigIndex, const SSmallInt4& sSite4, BYTE byFieldId)
{
    return F(3.0) - F(0.25) * _deviceCloverRetr(pDeviceData, sSite4, uiBigIndex, byMu, byNu, byFieldId);
}

#pragma endregion

#pragma region Chair term

/**
* (1/8) * Retr[()()+()()] = (1/8) * Retr[left+right]
* left(n) = Retr[(U_{a,b}(n)-U^+_{a,b}(n-a))(U_{b,c}(n)-U^+_{b,c}(n-c))]
* right(n) = Retr[(U^+_{a,b}(n-b)-U_{a,b}(n-a-b))(U^+_{b,c}(n-b)-U_{b,c}(n-b-c))]
*          = Retr[(U_{a,b}(n-b)-U^+_{a,b}(n-a-b))(U_{b,c}(n-b)-U^+_{b,c}(n-b-c))]
*          = left(n-b)
*/
static __device__ __inline__ Real _deviceChairTerm(const deviceSU3* __restrict__ pDeviceData,
    BYTE byFieldId, const SSmallInt4& sSite,
    BYTE mu, BYTE nu, BYTE rho, UINT uiBigIndex)
{
    const SSmallInt4& n_p_mu = _deviceSmallInt4OffsetC(sSite, __fwd(mu));
    const SSmallInt4& n_m_mu = _deviceSmallInt4OffsetC(sSite, __bck(mu));
    const SSmallInt4& n_p_nu = _deviceSmallInt4OffsetC(sSite, __fwd(nu));
    const SSmallInt4& n_m_nu = _deviceSmallInt4OffsetC(sSite, __bck(nu));
    const SSmallInt4& n_p_rho = _deviceSmallInt4OffsetC(sSite, __fwd(rho));
    const SSmallInt4& n_m_rho = _deviceSmallInt4OffsetC(sSite, __bck(rho));

    const SSmallInt4& n_p_mu_m_nu = _deviceSmallInt4OffsetC(n_p_mu, __bck(nu));
    const SSmallInt4& n_m_mu_p_nu = _deviceSmallInt4OffsetC(n_m_mu, __fwd(nu));
    const SSmallInt4& n_m_mu_m_nu = _deviceSmallInt4OffsetC(n_m_mu, __bck(nu));
    const SSmallInt4& n_m_rho_p_nu = _deviceSmallInt4OffsetC(n_m_rho, __fwd(nu));
    const SSmallInt4& n_m_rho_m_nu = _deviceSmallInt4OffsetC(n_m_rho, __bck(nu));
    const SSmallInt4& n_m_nu_p_rho = _deviceSmallInt4OffsetC(n_m_nu, __fwd(rho));

    const UINT n_bi4 = uiBigIndex * _DC_Dir;
    const UINT n_p_nu_bi4 = __bi4(n_p_nu);
    const UINT n_m_mu_bi4 = __bi4(n_m_mu);
    const UINT n_m_rho_bi4 = __bi4(n_m_rho);
    const UINT n_m_nu_bi4 = __bi4(n_m_nu);
    const UINT n_m_mu_m_nu_bi4 = __bi4(n_m_mu_m_nu);
    const UINT n_m_rho_m_nu_bi4 = __bi4(n_m_rho_m_nu);

    const SIndex& n__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_bi4 + mu];
    const SIndex& n_p_mu__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu) + nu];
    const SIndex& n_p_nu__rho = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_p_nu_bi4 + rho];
    const SIndex& n_m_mu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_mu_bi4 + mu];
    const SIndex& n_m_mu__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_mu_bi4 + nu];
    const SIndex& n_m_mu_p_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_mu_p_nu) + mu];
    const SIndex& n_m_rho__rho = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_rho_bi4 + rho];
    const SIndex& n_m_mu_m_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_mu_m_nu_bi4 + mu];
    const SIndex& n_m_nu__rho = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_nu_bi4 + rho];
    const SIndex& n_m_nu_p_rho__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_nu_p_rho) + nu];
    const SIndex& n_m_rho_m_nu__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_rho_m_nu_bi4 + nu];

    const SIndex n_m_mu__mu_dag = n_m_mu__mu.DaggerC();

    SIndex n_p_nu__mu_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_p_nu_bi4 + mu];
    SIndex n_p_rho__nu_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_rho) + nu];
    SIndex n__rho_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_bi4 + rho];
    SIndex n_m_rho_p_nu__rho_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_rho_p_nu) + rho];
    SIndex n_m_rho__nu_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_rho_bi4 + nu];
    SIndex n_p_mu_m_nu__nu_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu_m_nu) + nu];
    SIndex n_m_nu__mu_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_nu_bi4 + mu];
    SIndex n_m_mu_m_nu__nu_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_mu_m_nu_bi4 + nu];
    SIndex n_m_rho_m_nu__rho_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_rho_m_nu_bi4 + rho];

    n_p_nu__mu_dag.m_byTag = n_p_nu__mu_dag.m_byTag ^ _kDaggerOrOpposite;
    n_p_rho__nu_dag.m_byTag = n_p_rho__nu_dag.m_byTag ^ _kDaggerOrOpposite;
    n__rho_dag.m_byTag = n__rho_dag.m_byTag ^ _kDaggerOrOpposite;
    n_m_rho_p_nu__rho_dag.m_byTag = n_m_rho_p_nu__rho_dag.m_byTag ^ _kDaggerOrOpposite;
    n_m_rho__nu_dag.m_byTag = n_m_rho__nu_dag.m_byTag ^ _kDaggerOrOpposite;
    n_p_mu_m_nu__nu_dag.m_byTag = n_p_mu_m_nu__nu_dag.m_byTag ^ _kDaggerOrOpposite;
    n_m_nu__mu_dag.m_byTag = n_m_nu__mu_dag.m_byTag ^ _kDaggerOrOpposite;
    n_m_mu_m_nu__nu_dag.m_byTag = n_m_mu_m_nu__nu_dag.m_byTag ^ _kDaggerOrOpposite;
    n_m_rho_m_nu__rho_dag.m_byTag = n_m_rho_m_nu__rho_dag.m_byTag ^ _kDaggerOrOpposite;

    // U_{mu}(N) U_{nu}(N+mu) U^+_{mu}(n+nu)
    deviceSU3 term1(_deviceGetSTTerm(byFieldId, pDeviceData,
        n__mu, n_p_mu__nu, n_p_nu__mu_dag));
        //uiBigIndex, uiN_p_mu, uiN_p_nu, mu, nu, mu, 0, 0, 1));

    //U^+_{mu}(N-mu) U_{nu}(N-mu) U_{mu}(N-mu+nu)
    term1.Sub(_deviceGetSTTerm(byFieldId, pDeviceData,
        n_m_mu__mu_dag, n_m_mu__nu, n_m_mu_p_nu__mu));
        //uiN_m_mu, uiN_m_mu, uiN_m_mu_p_nu, mu, nu, mu, 1, 0, 0));

    // U_{rho}(N+nu) U^+_{nu}(N+rho) U^+_{rho}(N)
    deviceSU3 term2(_deviceGetSTTerm(byFieldId, pDeviceData,
        n_p_nu__rho, n_p_rho__nu_dag, n__rho_dag));
        //uiN_p_nu, uiN_p_rho, uiBigIndex, rho, nu, rho, 0, 1, 1));

    // U^+_{rho}(N+nu-rho) U^+_{nu}(N-rho) U_{rho}(N-rho)
    term2.Sub(_deviceGetSTTerm(byFieldId, pDeviceData,
        n_m_rho_p_nu__rho_dag, n_m_rho__nu_dag, n_m_rho__rho));
        //uiN_m_rho_p_nu, uiN_m_rho, uiN_m_rho, rho, nu, rho, 1, 1, 0));

    term1.Mul(term2);

    //pm mu, nu
    //U(mu,-nu) = U(N) U(N+mu-nu) U(N-nu) U(N-nu), 0110
    deviceSU3 term3(_deviceGetSTTerm(byFieldId, pDeviceData,
        n__mu, n_p_mu_m_nu__nu_dag, n_m_nu__mu_dag));
        //uiBigIndex, uiN_p_mu_m_nu, uiN_m_nu, mu, nu, mu, 0, 1, 1));

    //mm
    //U(-mu, -nu) = U(N - mu) U(N - mu - nu) U(N - mu - nu) U(N - nu) 1100
    term3.Sub(_deviceGetSTTerm(byFieldId, pDeviceData,
        n_m_mu__mu_dag, n_m_mu_m_nu__nu_dag, n_m_mu_m_nu__mu));
        //uiN_m_mu, uiN_m_mu_m_nu, uiN_m_mu_m_nu, mu, nu, mu, 1, 1, 0));

    //mp, nu, rho
    //mp = U(-mu,nu) = U^+_{mu}(N-mu) U_{nu}(N-mu) U_{mu}(N-mu+nu) U^+_{nu}(N)
    deviceSU3 term4(_deviceGetSTTerm(byFieldId, pDeviceData,
        n_m_nu__rho, n_m_nu_p_rho__nu, n__rho_dag));
        //uiN_m_nu, uiN_m_nu_p_rho, uiBigIndex, rho, nu, rho, 0, 0, 1));

    //mm nu rho
    //U(-mu, -nu) = U(N - mu) U(N - mu - nu) U(N - mu - nu) U(N - nu) 1100
    term4.Sub(_deviceGetSTTerm(byFieldId, pDeviceData,
        n_m_rho_m_nu__rho_dag, n_m_rho_m_nu__nu, n_m_rho__rho));
        //uiN_m_rho_m_nu, uiN_m_rho_m_nu, uiN_m_rho, rho, nu, rho, 1, 0, 0));

    term3.Mul(term4);

    term1.Add(term3);

    return term1.ReTr();
}

#pragma endregion

#pragma endregion

#pragma region Force

#pragma region Plaqutte term



/**
* g1=O^2(x^2)/2
* g2=O^2(y^2)/2
* g3=O^2(x^2+y^2)
* For identity Dirichlet boundary, if site is out of boundary, {I}_TA = 0
* So we do not care whether site is out of boundary
* Note that, for x+1, it dose NOT always mean x+1
* For g1, g2, site offset is x+1 site and y+1 site,
* for g3, sSiteOffset is not using
*/
static __device__ __inline__ Real _deviceGi(
    const SSmallInt4& sCenter,
    const SSmallInt4& sSite,
    const SSmallInt4& sSiteOffset,
    const SIndex& uiSiteBI,
    const SIndex& uiSiteOffsetBI,
    BYTE i,
    Real fOmegaSq)
{
    if (0 == i)
    {
        const Real fX = uiSiteBI.IsDirichlet() ? F(0.0)
            : static_cast<Real>(sSite.x - sCenter.x);
        return F(0.5) * fOmegaSq * (fX * fX);
        //const Real fXp1 = uiSiteOffsetBI.IsDirichlet() ? F(0.0)
        //    : static_cast<Real>(sSiteOffset.x - sCenter.x);
        //return F(0.5) * fOmegaSq * (fX * fX + fXp1 * fXp1);
    }
    else if (1 == i)
    {
        const Real fY = uiSiteBI.IsDirichlet() ? F(0.0)
            : static_cast<Real>(sSite.y - sCenter.y);
        return F(0.5) * fOmegaSq * (fY * fY);
        //const Real fYp1 = uiSiteOffsetBI.IsDirichlet() ? F(0.0)
        //    : static_cast<Real>(sSiteOffset.y - sCenter.y);
        //return F(0.5) * fOmegaSq * (fY * fY + fYp1 * fYp1);
    }
    const Real fX = uiSiteBI.IsDirichlet() ? F(0.0)
        : static_cast<Real>(sSite.x - sCenter.x);
    const Real fY = uiSiteOffsetBI.IsDirichlet() ? F(0.0)
        : static_cast<Real>(sSite.y - sCenter.y);
    const Real fXp1 = uiSiteOffsetBI.IsDirichlet() ? F(0.0)
        : static_cast<Real>(sSiteOffset.x - sCenter.x);
    const Real fYp1 = uiSiteOffsetBI.IsDirichlet() ? F(0.0)
        : static_cast<Real>(sSiteOffset.y - sCenter.y);
    return F(0.5) * fOmegaSq * (fX * fX + fY * fY + fXp1 * fXp1 + fYp1 * fYp1);
}

/**
* Coefficient = (f(n)+f(n+mu)+f(n+nu)+f(n+mu+nu))/4
* Simplfy: nu is always t direction, so f(n) = f(n+nu), f(n+mu) = f(n+mu+nu)
* Coefficient = (f(n)+f(n+mu))/2
* For 3 == mu, f(n) = f(n+mu)
* This is also true for Dirichlet boundary condition, only Dirichlet on X-Y direction is assumed
*
* ==================================================
* Note for periodic boundary condition:
* For const SSmallInt4 sN_p_m = _deviceSmallInt4OffsetC(sSite4, mu + 1)
* sN_p_m.mu can be -1, which leads to a wrong (sN_p_m.y - sCenter.y)
* This '-1' should be set to L_mu - 1. If we consider add the plaquttes as clovers,
* then the coordinates of the centers of the clovers will always be in the lattice,
* so should be set to L_mu - 1
*/
static __device__ __inline__ Real _deviceFi(
    BYTE byFieldId,
    const SSmallInt4& sSite4,
    const SSmallInt4& sCenter,
    UINT uiN, BYTE i, BYTE mu, BYTE nu)
{
    const SSmallInt4 sN_p_mu = _deviceSmallInt4OffsetC(sSite4, mu + 1);
    const SIndex& n_p_mu__idx = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(sN_p_mu)];
    const SSmallInt4 site_N_p_mu = __deviceSiteIndexToInt4(n_p_mu__idx.m_uiSiteIndex);

    const SSmallInt4 sN_p_nu = _deviceSmallInt4OffsetC(sSite4, nu + 1);
    const SIndex& n_p_nu__idx = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(sN_p_nu)];
    const SSmallInt4 site_N_p_nu = __deviceSiteIndexToInt4(n_p_nu__idx.m_uiSiteIndex);

    const SSmallInt4 sN_p_numu = _deviceSmallInt4OffsetC(sN_p_mu, nu + 1);
    const SIndex& n_p_numu__idx = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(sN_p_numu)];
    const SSmallInt4 site_N_p_munu = __deviceSiteIndexToInt4(n_p_numu__idx.m_uiSiteIndex);

    const UBOOL bN_surface = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiN].IsDirichlet();
    const UBOOL bN_p_mu_surface = n_p_mu__idx.IsDirichlet();
    const UBOOL bN_p_nu_surface = n_p_nu__idx.IsDirichlet();
    const UBOOL bN_p_munu_surface = n_p_numu__idx.IsDirichlet();

    const INT x1 = bN_surface ? 0 : (sSite4.x - sCenter.x);
    const INT y1 = bN_surface ? 0 : (sSite4.y - sCenter.y);

    const INT x2 = bN_p_mu_surface ? 0 : (site_N_p_mu.x - sCenter.x);
    const INT y2 = bN_p_mu_surface ? 0 : (site_N_p_mu.y - sCenter.y);

    const INT x3 = bN_p_nu_surface ? 0 : (site_N_p_nu.x - sCenter.x);
    const INT y3 = bN_p_nu_surface ? 0 : (site_N_p_nu.y - sCenter.y);

    const INT x4 = bN_p_munu_surface ? 0 : (site_N_p_munu.x - sCenter.x);
    const INT y4 = bN_p_munu_surface ? 0 : (site_N_p_munu.y - sCenter.y);

    if (0 == i)
    {

        return F(0.25) * static_cast<Real>(x1 * x1 + y1 * y1
            + x2 * x2 + y2 * y2
            + x3 * x3 + y3 * y3
            + x4 * x4 + y4 * y4);
    }

    if (1 == i)
    {
        return F(0.25) * static_cast<Real>(
              y1 * y1
            + y2 * y2
            + y3 * y3
            + y4 * y4);
    }
    return F(0.25) * static_cast<Real>(
          x1 * x1
        + x2 * x2
        + x3 * x3
        + x4 * x4);
}

static __device__ __inline__ Real _deviceFiShifted(
    BYTE byFieldId,
    const SSmallInt4& sSite4,
    const SSmallInt4& sCenter,
    BYTE i, BYTE mu, BYTE nu)
{
    const SIndex& n__idx = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(sSite4)];
    const SSmallInt4 site_N = __deviceSiteIndexToInt4(n__idx.m_uiSiteIndex);

    const SSmallInt4 sN_p_mu = _deviceSmallInt4OffsetC(sSite4, mu + 1);
    const SIndex& n_p_mu__idx = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(sN_p_mu)];
    const SSmallInt4 site_N_p_mu = __deviceSiteIndexToInt4(n_p_mu__idx.m_uiSiteIndex);

    const SSmallInt4 sN_p_nu = _deviceSmallInt4OffsetC(sSite4, nu + 1);
    const SIndex& n_p_nu__idx = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(sN_p_nu)];
    const SSmallInt4 site_N_p_nu = __deviceSiteIndexToInt4(n_p_nu__idx.m_uiSiteIndex);

    const SSmallInt4 sN_p_numu = _deviceSmallInt4OffsetC(sN_p_mu, nu + 1);
    const SIndex& n_p_numu__idx = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(sN_p_numu)];
    const SSmallInt4 site_N_p_munu = __deviceSiteIndexToInt4(n_p_numu__idx.m_uiSiteIndex);

    //const UBOOL bN_surface = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiN].IsDirichlet();
    //const UBOOL bN_p_mu_surface = n_p_mu__idx.IsDirichlet();
    //const UBOOL bN_p_nu_surface = n_p_nu__idx.IsDirichlet();
    //const UBOOL bN_p_munu_surface = n_p_numu__idx.IsDirichlet();

    const Real x1 = static_cast<Real>(site_N.x - sCenter.x + F(0.5));
    const Real y1 = static_cast<Real>(site_N.y - sCenter.y + F(0.5));

    const Real x2 = static_cast<Real>(site_N_p_mu.x - sCenter.x + F(0.5));
    const Real y2 = static_cast<Real>(site_N_p_mu.y - sCenter.y + F(0.5));

    const Real x3 = static_cast<Real>(site_N_p_nu.x - sCenter.x + F(0.5));
    const Real y3 = static_cast<Real>(site_N_p_nu.y - sCenter.y + F(0.5));

    const Real x4 = static_cast<Real>(site_N_p_munu.x - sCenter.x + F(0.5));
    const Real y4 = static_cast<Real>(site_N_p_munu.y - sCenter.y + F(0.5));

    if (0 == i)
    {
        //const UBOOL bCorner = (sSite4.x == site_N_p_munu.x) && (sSite4.y == site_N_p_munu.y);
        //if (bCorner)
        //{
        //    return F(0.0);
        //}
        return F(0.25) * (x1 * x1 + y1 * y1
            + x2 * x2 + y2 * y2
            + x3 * x3 + y3 * y3
            + x4 * x4 + y4 * y4);
    }

    if (1 == i)
    {
        return F(0.25) * (y1 * y1
            + y2 * y2
            + y3 * y3
            + y4 * y4);
    }
    return F(0.25) * (x1 * x1
        + x2 * x2
        + x3 * x3
        + x4 * x4);
}

/**
 * Staple for U_mu, from U_{mu,nu}
 */
static __device__ __inline__ deviceSU3 _deviceStapleTermGfactor(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, Real fOmegaSq,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE i, UBOOL bShifted = FALSE)
{
    const SSmallInt4 n_p_mu = _deviceSmallInt4OffsetC(sSite, __fwd(mu));
    const SSmallInt4 n_p_nu = _deviceSmallInt4OffsetC(sSite, __fwd(nu));
    const SSmallInt4 n_m_nu = _deviceSmallInt4OffsetC(sSite, __bck(nu));
    const SSmallInt4 n_p_mu_m_nu = _deviceSmallInt4OffsetC(n_m_nu, __fwd(mu));

    const SIndex& n__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][uiBigIndex * _DC_Dir + nu];
    const SIndex& n_p_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_nu) + mu];
    SIndex n_p_mu__nu_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu) + nu];
    n_p_mu__nu_dag.m_byTag = n_p_mu__nu_dag.m_byTag ^ _kDaggerOrOpposite;

    const UINT n_m_nu_bi4 = __bi4(n_m_nu);
    SIndex n_m_nu__nu_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_nu_bi4 + nu];
    n_m_nu__nu_dag.m_byTag = n_m_nu__nu_dag.m_byTag ^ _kDaggerOrOpposite;
    const SIndex& n_m_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_nu_bi4 + mu];
    const SIndex& n_p_mu_m_nu__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu_m_nu) + nu];

    deviceSU3 left(
        _deviceGetSTTerm(byFieldId, pDeviceData,
            //pDeviceData, uiBigIndex, uiN_p_nu, uiN_p_mu, nu, mu, nu, 0, 0, 1
            n__nu, n_p_nu__mu, n_p_mu__nu_dag
        ));
    deviceSU3 right(
        _deviceGetSTTerm(byFieldId, pDeviceData,
            //pDeviceData, uiN_m_nu, uiN_m_nu, uiN_p_mu_m_nu, nu, mu, nu, 1, 0, 0
            n_m_nu__nu_dag, n_m_nu__mu, n_p_mu_m_nu__nu
        ));

    const Real fLFactor = bShifted
        ? _deviceFiShifted(byFieldId, sSite, sCenter, i, mu, nu)
        : _deviceFi(byFieldId, sSite, sCenter, uiBigIndex, i, mu, nu);
    const Real fRFactor = bShifted
        ? _deviceFiShifted(byFieldId, n_m_nu, sCenter, i, mu, nu)
        : _deviceFi(byFieldId, n_m_nu, sCenter, __bi(n_m_nu), i, mu, nu);
    
    left.MulReal(fLFactor * fOmegaSq);
    right.MulReal(fRFactor * fOmegaSq);
    left.Add(right);

    return left;
}

#pragma endregion

#pragma region Chair terms

/**
* U(N) U(N+rho) U(N+nu) - U(N-rho) U(N-rho) U(N-rho+nu)
* rho nu rho
* + + -, - + +
*/
static __device__ __inline__ deviceSU3 _deviceS1(BYTE byFieldId, 
    const deviceSU3* __restrict__ pDeviceData, const SSmallInt4& sSite,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho)
{
    const SSmallInt4 n_p_rho = _deviceSmallInt4OffsetC(sSite, __fwd(rho));
    const SSmallInt4 n_p_nu = _deviceSmallInt4OffsetC(sSite, __fwd(nu));
    const SSmallInt4 n_m_rho = _deviceSmallInt4OffsetC(sSite, __bck(rho));
    const SSmallInt4 n_m_rho_p_nu = _deviceSmallInt4OffsetC(n_m_rho, __fwd(nu));

    const UINT n_m_rho_bi4 = __bi4(n_m_rho);

    const SIndex& n__rho = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][uiBigIndex * _DC_Dir + rho];
    const SIndex& n_p_rho__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_rho) + nu];
    const SIndex& n_m_rho__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_rho_bi4 + nu];
    const SIndex& n_m_rho_p_nu__rho = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_rho_p_nu) + rho];

    SIndex n_p_nu__rho_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_nu) + rho];
    n_p_nu__rho_dag.m_byTag = n_p_nu__rho_dag.m_byTag ^ _kDaggerOrOpposite;
    SIndex n_m_rho__rho_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_rho_bi4 + rho];
    n_m_rho__rho_dag.m_byTag = n_m_rho__rho_dag.m_byTag ^ _kDaggerOrOpposite;

    deviceSU3 left(
        _deviceGetSTTerm(byFieldId, pDeviceData,
            //pDeviceData, uiBigIndex, uiN_p_rho, uiN_p_nu, rho, nu, rho, 0, 0, 1
            n__rho, n_p_rho__nu, n_p_nu__rho_dag
        ));
    left.Sub(
        _deviceGetSTTerm(byFieldId, pDeviceData,
//            pDeviceData, uiN_m_rho, uiN_m_rho, uiN_m_rho_p_nu, rho, nu, rho, 1, 0, 0
                n_m_rho__rho_dag, n_m_rho__nu, n_m_rho_p_nu__rho
        ));
    return left;
}

/**
* U(N) U(N-nu+rho) U(N-nu) - U(N-rho) U(N-rho-nu) U(N-rho-nu)
* rho nu rho
* + - -, - - +
*/
static __device__ __inline__ deviceSU3 _deviceS2(BYTE byFieldId, 
    const deviceSU3* __restrict__ pDeviceData, const SSmallInt4& sSite,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho)
{
    const SSmallInt4 n_m_nu = _deviceSmallInt4OffsetC(sSite, __bck(nu));
    const SSmallInt4 n_m_nu_p_rho = _deviceSmallInt4OffsetC(n_m_nu, __fwd(rho));
    const SSmallInt4 n_m_rho = _deviceSmallInt4OffsetC(sSite, __bck(rho));
    const SSmallInt4 n_m_rho_m_nu = _deviceSmallInt4OffsetC(n_m_rho, __bck(nu));

    const UINT n_m_rho_m_nu_bi4 = __bi4(n_m_rho_m_nu);

    const SIndex& n__rho = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][uiBigIndex * _DC_Dir + rho];
    const SIndex& n_m_rho_m_nu__rho = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_rho_m_nu_bi4 + rho];

    SIndex n_m_nu_p_rho__nu_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_nu_p_rho) + nu];
    SIndex n_m_nu__rho_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_nu) + rho];
    SIndex n_m_rho__rho_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_rho) + rho];
    SIndex n_m_rho_m_nu__nu_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_rho_m_nu_bi4 + nu];

    n_m_nu_p_rho__nu_dag.m_byTag = n_m_nu_p_rho__nu_dag.m_byTag ^ _kDaggerOrOpposite;
    n_m_nu__rho_dag.m_byTag = n_m_nu__rho_dag.m_byTag ^ _kDaggerOrOpposite;
    n_m_rho__rho_dag.m_byTag = n_m_rho__rho_dag.m_byTag ^ _kDaggerOrOpposite;
    n_m_rho_m_nu__nu_dag.m_byTag = n_m_rho_m_nu__nu_dag.m_byTag ^ _kDaggerOrOpposite;

    deviceSU3 left(
        _deviceGetSTTerm(byFieldId, pDeviceData,
            n__rho, n_m_nu_p_rho__nu_dag, n_m_nu__rho_dag
            //pDeviceData, uiBigIndex, uiN_m_nu_p_rho, uiN_m_nu, rho, nu, rho, 0, 1, 1
        ));
    left.Sub(
        _deviceGetSTTerm(byFieldId, pDeviceData,
            //pDeviceData, uiN_m_rho, uiN_m_rho_m_nu, uiN_m_rho_m_nu, rho, nu, rho, 1, 1, 0
            n_m_rho__rho_dag, n_m_rho_m_nu__nu_dag, n_m_rho_m_nu__rho
        ));
    return left;
}

/**
* U(N+mu-rho+nu) U(N+mu-rho) U(N+mu-rho) - U(N+mu+nu) U(N+mu+rho) U(N+mu)
* rho nu rho
* - - +, + - -
*/
static __device__ __inline__ deviceSU3 _deviceS3(BYTE byFieldId, 
    const deviceSU3* __restrict__ pDeviceData, const SSmallInt4& sSite,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho)
{
    const SSmallInt4 n_p_mu = _deviceSmallInt4OffsetC(sSite, __fwd(mu));
    const SSmallInt4 n_p_mu_m_rho = _deviceSmallInt4OffsetC(n_p_mu, __bck(rho));
    const SSmallInt4 n_p_mu_p_rho = _deviceSmallInt4OffsetC(n_p_mu, __fwd(rho));
    const SSmallInt4 n_p_mu_p_nu = _deviceSmallInt4OffsetC(n_p_mu, __fwd(nu));
    const SSmallInt4 n_p_mu_m_rho_p_nu = _deviceSmallInt4OffsetC(n_p_mu_m_rho, __fwd(nu));

    const UINT n_p_mu_m_rho_bi4 = __bi4(n_p_mu_m_rho);

    const SIndex& n_p_mu_m_rho__rho = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_p_mu_m_rho_bi4 + rho];
    const SIndex& n_p_mu_p_nu__rho = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu_p_nu) + rho];

    SIndex n_p_mu_m_rho_p_nu__rho_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu_m_rho_p_nu) + rho];
    SIndex n_p_mu_m_rho__nu_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_p_mu_m_rho_bi4 + nu];
    SIndex n_p_mu_p_rho__nu_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu_p_rho) + nu];
    SIndex n_p_mu__rho_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu) + rho];

    n_p_mu_m_rho_p_nu__rho_dag.m_byTag = n_p_mu_m_rho_p_nu__rho_dag.m_byTag ^ _kDaggerOrOpposite;
    n_p_mu_m_rho__nu_dag.m_byTag = n_p_mu_m_rho__nu_dag.m_byTag ^ _kDaggerOrOpposite;
    n_p_mu_p_rho__nu_dag.m_byTag = n_p_mu_p_rho__nu_dag.m_byTag ^ _kDaggerOrOpposite;
    n_p_mu__rho_dag.m_byTag = n_p_mu__rho_dag.m_byTag ^ _kDaggerOrOpposite;

    deviceSU3 left(
        _deviceGetSTTerm(byFieldId, pDeviceData,
            //pDeviceData, uiN_p_mu_m_rho_p_nu, uiN_p_mu_m_rho, uiN_p_mu_m_rho, rho, nu, rho, 1, 1, 0
            n_p_mu_m_rho_p_nu__rho_dag, n_p_mu_m_rho__nu_dag, n_p_mu_m_rho__rho
        ));
    left.Sub(
        _deviceGetSTTerm(byFieldId, pDeviceData,
            n_p_mu_p_nu__rho, n_p_mu_p_rho__nu_dag, n_p_mu__rho_dag
            //pDeviceData, uiN_p_mu_p_nu, uiN_p_mu_p_rho, uiN_p_mu, rho, nu, rho, 0, 1, 1
        ));

    return left;

}

/**
* U(N+mu-rho-nu) U(N+mu-rho-nu) U(N+mu-rho) - U(N+mu-nu) U(N+mu+rho-nu) U(N+mu)
* rho nu rho
* - + +, + + -
*/
static __device__ __inline__ deviceSU3 _deviceS4(BYTE byFieldId, 
    const deviceSU3* __restrict__ pDeviceData, const SSmallInt4& sSite,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho)
{
    const SSmallInt4 n_p_mu = _deviceSmallInt4OffsetC(sSite, __fwd(mu));
    const SSmallInt4 n_p_mu_m_rho = _deviceSmallInt4OffsetC(n_p_mu, __bck(rho));
    const SSmallInt4 n_p_mu_m_nu = _deviceSmallInt4OffsetC(n_p_mu, __bck(nu));
    const SSmallInt4 n_p_mu_m_rho_m_nu = _deviceSmallInt4OffsetC(n_p_mu_m_nu, __bck(rho));
    const SSmallInt4 n_p_mu_p_rho_m_nu = _deviceSmallInt4OffsetC(n_p_mu_m_nu, __fwd(rho));

    const UINT n_p_mu_m_rho_m_nu_bi4 = __bi4(n_p_mu_m_rho_m_nu);

    const SIndex& n_p_mu_m_rho_m_nu__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_p_mu_m_rho_m_nu_bi4 + nu];
    const SIndex& n_p_mu_m_rho__rho = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu_m_rho) + rho];
    const SIndex& n_p_mu_m_nu__rho = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu_m_nu) + rho];
    const SIndex& n_p_mu_p_rho_m_nu__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu_p_rho_m_nu) + nu];

    SIndex n_p_mu_m_rho_m_nu__rho_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_p_mu_m_rho_m_nu_bi4 + rho];
    SIndex n_p_mu__rho_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu) + rho];

    n_p_mu_m_rho_m_nu__rho_dag.m_byTag = n_p_mu_m_rho_m_nu__rho_dag.m_byTag ^ _kDaggerOrOpposite;
    n_p_mu__rho_dag.m_byTag = n_p_mu__rho_dag.m_byTag ^ _kDaggerOrOpposite;

    deviceSU3 left(
        _deviceGetSTTerm(byFieldId, pDeviceData,
            n_p_mu_m_rho_m_nu__rho_dag, n_p_mu_m_rho_m_nu__nu, n_p_mu_m_rho__rho
            //pDeviceData, uiN_p_mu_m_rho_m_nu, uiN_p_mu_m_rho_m_nu, uiN_p_mu_m_rho, rho, nu, rho, 1, 0, 0
        ));
    left.Sub(
        _deviceGetSTTerm(byFieldId, pDeviceData,
            n_p_mu_m_nu__rho, n_p_mu_p_rho_m_nu__nu, n_p_mu__rho_dag
            //pDeviceData, uiN_p_mu_m_nu, uiN_p_mu_p_rho_m_nu, uiN_p_mu, rho, nu, rho, 0, 0, 1
        ));

    return left;
}

/**
* U(N+mu-rho) U(N+mu-rho) U(N+mu-rho+nu) - U(N+mu) U(N+mu+rho) U(N+mu+nu)
* rho nu rho
* - + +, + + -
*/
static __device__ __inline__ deviceSU3 _deviceT1(BYTE byFieldId, 
    const deviceSU3* __restrict__ pDeviceData, const SSmallInt4& sSite,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho)
{
    const SSmallInt4 n_p_mu = _deviceSmallInt4OffsetC(sSite, __fwd(mu));
    const SSmallInt4 n_p_mu_m_rho = _deviceSmallInt4OffsetC(n_p_mu, __bck(rho));
    const SSmallInt4 n_p_mu_p_rho = _deviceSmallInt4OffsetC(n_p_mu, __fwd(rho));
    const SSmallInt4 n_p_mu_p_nu = _deviceSmallInt4OffsetC(n_p_mu, __fwd(nu));
    const SSmallInt4 n_p_mu_m_rho_p_nu = _deviceSmallInt4OffsetC(n_p_mu_m_rho, __fwd(nu));

    const UINT n_p_mu_m_rho_bi4 = __bi4(n_p_mu_m_rho);

    const SIndex& n_p_mu_m_rho__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_p_mu_m_rho_bi4 + nu];
    const SIndex& n_p_mu_m_rho_p_nu__rho = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu_m_rho_p_nu) + rho];
    const SIndex& n_p_mu__rho = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu) + rho];
    const SIndex& n_p_mu_p_rho__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu_p_rho) + nu];

    SIndex n_p_mu_m_rho__rho_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_p_mu_m_rho_bi4 + rho];
    SIndex n_p_mu_p_nu__rho_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu_p_nu) + rho];

    n_p_mu_m_rho__rho_dag.m_byTag = n_p_mu_m_rho__rho_dag.m_byTag ^ _kDaggerOrOpposite;
    n_p_mu_p_nu__rho_dag.m_byTag = n_p_mu_p_nu__rho_dag.m_byTag ^ _kDaggerOrOpposite;

    deviceSU3 left(
        _deviceGetSTTerm(byFieldId, pDeviceData,
            n_p_mu_m_rho__rho_dag, n_p_mu_m_rho__nu, n_p_mu_m_rho_p_nu__rho
            //pDeviceData, uiN_p_mu_m_rho, uiN_p_mu_m_rho, uiN_p_mu_m_rho_p_nu, rho, nu, rho, 1, 0, 0
        ));
    left.Sub(
        _deviceGetSTTerm(byFieldId, pDeviceData,
            n_p_mu__rho, n_p_mu_p_rho__nu, n_p_mu_p_nu__rho_dag
            //pDeviceData, uiN_p_mu, uiN_p_mu_p_rho, uiN_p_mu_p_nu, rho, nu, rho, 0, 0, 1
        ));

    return left;
}

/**
* U(N-mu) U(N-mu+rho) U(N-mu+nu) - U(N-mu-rho) U(N-mu-rho) U(N-mu-rho+nu)
* rho nu rho
* + + -, - + +
*/
static __device__ __inline__ deviceSU3 _deviceT2(BYTE byFieldId, 
    const deviceSU3* __restrict__ pDeviceData, const SSmallInt4& sSite,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho)
{
    const SSmallInt4 n_m_mu = _deviceSmallInt4OffsetC(sSite, __bck(mu));
    const SSmallInt4 n_m_mu_m_rho = _deviceSmallInt4OffsetC(n_m_mu, __bck(rho));
    const SSmallInt4 n_m_mu_p_rho = _deviceSmallInt4OffsetC(n_m_mu, __fwd(rho));
    const SSmallInt4 n_m_mu_p_nu = _deviceSmallInt4OffsetC(n_m_mu, __fwd(nu));
    const SSmallInt4 n_m_mu_p_nu_m_rho = _deviceSmallInt4OffsetC(n_m_mu_m_rho, __fwd(nu));

    const UINT n_m_mu_m_rho_bi4 = __bi4(n_m_mu_m_rho);

    const SIndex& n_m_mu__rho = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_mu) + rho];
    const SIndex& n_m_mu_p_rho__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_mu_p_rho) + nu];
    const SIndex& n_m_mu_m_rho__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_mu_m_rho_bi4 + nu];
    const SIndex& n_m_mu_p_nu_m_rho__rho = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_mu_p_nu_m_rho) + rho];

    SIndex n_m_mu_p_nu__rho_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_mu_p_nu) + rho];
    SIndex n_m_mu_m_rho__rho_dag = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_mu_m_rho_bi4 + rho];

    n_m_mu_p_nu__rho_dag.m_byTag = n_m_mu_p_nu__rho_dag.m_byTag ^ _kDaggerOrOpposite;
    n_m_mu_m_rho__rho_dag.m_byTag = n_m_mu_m_rho__rho_dag.m_byTag ^ _kDaggerOrOpposite;

    deviceSU3 left(
        _deviceGetSTTerm(byFieldId, pDeviceData,
            n_m_mu__rho, n_m_mu_p_rho__nu, n_m_mu_p_nu__rho_dag
            //pDeviceData, uiN_m_mu, uiN_m_mu_p_rho, uiN_m_mu_p_nu, rho, nu, rho, 0, 0, 1
        ));
    left.Sub(
        _deviceGetSTTerm(byFieldId, pDeviceData,
            n_m_mu_m_rho__rho_dag, n_m_mu_m_rho__nu, n_m_mu_p_nu_m_rho__rho
            //pDeviceData, uiN_m_mu_m_rho, uiN_m_mu_m_rho, uiN_m_mu_p_nu_m_rho, rho, nu, rho, 1, 0, 0
        ));
    return left;
}

/**
* i = 0, 1, 2 correspond to x, y and xy
* h_i(N) = x or y or xy
* return h_i(N) + h_i(N + nu), where N is site, and N + nu (or N + mu or ...) is site2
*/
static __device__ __inline__ Real _deviceHi(
    const SSmallInt4 &center,
    const SSmallInt4 &site, const SSmallInt4 &site2,
    const SIndex& uiSiteBI, const SIndex& uiSite2BI, BYTE i)
{
    if (0 == i)
    {
        const Real fX1 = uiSiteBI.IsDirichlet() ? F(0.0)
            : static_cast<Real>(site.x - center.x);
        const Real fX2 = uiSite2BI.IsDirichlet() ? F(0.0)
            : static_cast<Real>(site2.x - center.x);
        return fX1 + fX2;
    }
    else if (1 == i)
    {
        const Real fY1 = uiSiteBI.IsDirichlet() ? F(0.0)
            : static_cast<Real>(site.y - center.y);
        const Real fY2 = uiSite2BI.IsDirichlet() ? F(0.0)
            : static_cast<Real>(site2.y - center.y);
        return -fY1 - fY2;
    }
    const Real fX1 = uiSiteBI.IsDirichlet() ? F(0.0)
        : static_cast<Real>(site.x - center.x);
    const Real fX2 = uiSite2BI.IsDirichlet() ? F(0.0)
        : static_cast<Real>(site2.x - center.x);
    const Real fY1 = uiSiteBI.IsDirichlet() ? F(0.0)
        : static_cast<Real>(site.y - center.y);
    const Real fY2 = uiSite2BI.IsDirichlet() ? F(0.0)
        : static_cast<Real>(site2.y - center.y);
    return fX1 * fY1 + fX2 * fY2;
}

/**
* [hi(n)+hi(n+nu)]S1  U(N+nu) U(N+mu)
* mu nu
* - +,
*/
static __device__ __inline__ deviceSU3 _deviceStapleS1(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    const SSmallInt4 n_p_mu = _deviceSmallInt4OffsetC(sSite, mu + 1);
    const SSmallInt4 n_p_nu = _deviceSmallInt4OffsetC(sSite, nu + 1);
    const UINT uiN_p_nu = __bi(n_p_nu);
    const SIndex& n_p_mu__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu) + nu];
    const SIndex& n_p_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][uiN_p_nu * _DC_Dir + mu];
    const SIndex& uiSiteN_p_nu = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiN_p_nu];

    deviceSU3 ret(_deviceS1(byFieldId, pDeviceData, sSite, uiBigIndex, mu, nu, rho));
    ret.Mul(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_p_nu__mu, byFieldId));
    ret.MulDagger(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_p_mu__nu, byFieldId));

    ret.MulReal(_deviceHi(sCenter,
        sSite,
        __deviceSiteIndexToInt4(uiSiteN_p_nu.m_uiSiteIndex),
        __idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiBigIndex], uiSiteN_p_nu, i));

    return ret;
}

/**
* [h(N) + h(n-nu)] S2 U(n-nu)U(n+mu-nu)
* mu nu
* + +
*/
static __device__ __inline__ deviceSU3 _deviceStapleS2(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    const SSmallInt4 n_m_nu = _deviceSmallInt4OffsetC(sSite, __bck(nu));
    const SSmallInt4 n_m_nu_p_mu = _deviceSmallInt4OffsetC(n_m_nu, __fwd(mu));
    const UINT uiN_m_nu = __bi(n_m_nu);
    const SIndex& n_m_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][uiN_m_nu * _DC_Dir + mu];
    const SIndex& n_m_nu_p_mu__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_nu_p_mu)+ nu];

    const SIndex& uiSiteN_m_nu = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiN_m_nu];

    deviceSU3 ret(_deviceS2(byFieldId, pDeviceData, sSite, uiBigIndex, mu, nu, rho));
    ret.Mul(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_m_nu__mu, byFieldId));
    ret.Mul(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_m_nu_p_mu__nu, byFieldId));

    ret.MulReal(_deviceHi(sCenter,
        sSite,
        __deviceSiteIndexToInt4(uiSiteN_m_nu.m_uiSiteIndex),
        __idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiBigIndex], uiSiteN_m_nu, i));

    return ret;
}

/**
* [h(N+mu) + h(N+mu+nu)]U(n) U(n+nu) S3
* nu mu
* + +
*/
static __device__ __inline__ deviceSU3 _deviceStapleS3(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    const SSmallInt4 n_p_mu = _deviceSmallInt4OffsetC(sSite, __fwd(mu));
    const SSmallInt4 n_p_mu_p_nu = _deviceSmallInt4OffsetC(n_p_mu, __fwd(nu));
    const SSmallInt4 n_p_nu = _deviceSmallInt4OffsetC(sSite, __fwd(nu));

    const UINT uiN_p_mu = __bi(n_p_mu);
    const UINT uiN_p_mu_p_nu = __bi(n_p_mu_p_nu);

    const SIndex& n__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][uiBigIndex * _DC_Dir + nu];
    const SIndex& n_p_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_nu) + mu];

    const SIndex& uiSiteN_p_mu = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiN_p_mu];
    const SIndex& uiSiteN_p_mu_p_nu = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiN_p_mu_p_nu];

    deviceSU3 ret(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n__nu, byFieldId));
    ret.Mul(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_p_nu__mu, byFieldId));
    ret.Mul(_deviceS3(byFieldId, pDeviceData, sSite, uiBigIndex, mu, nu, rho));

    ret.MulReal(_deviceHi(sCenter,
        __deviceSiteIndexToInt4(uiSiteN_p_mu.m_uiSiteIndex),
        __deviceSiteIndexToInt4(uiSiteN_p_mu_p_nu.m_uiSiteIndex),
        uiSiteN_p_mu, uiSiteN_p_mu_p_nu, i));

    return ret;

}

/**
* [h(N+mu) + h(N+mu-nu)] U(n-nu) U(n-nu) S4
* nu mu
* - +
*/
static __device__ __inline__ deviceSU3 _deviceStapleS4(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    const SSmallInt4 n_p_mu = _deviceSmallInt4OffsetC(sSite, __fwd(mu));
    const SSmallInt4 n_p_mu_m_nu = _deviceSmallInt4OffsetC(n_p_mu, __bck(nu));
    const SSmallInt4 n_m_nu = _deviceSmallInt4OffsetC(sSite, __bck(nu));

    const UINT uiN_p_mu = __bi(n_p_mu);
    const UINT uiN_p_mu_m_nu = __bi(n_p_mu_m_nu);
    const UINT n_m_nu_bi4 = __bi4(n_m_nu);

    const SIndex& n_m_nu__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_nu_bi4 + nu];
    const SIndex& n_m_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_nu_bi4 + mu];

    const SIndex& uiSiteN_p_mu = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiN_p_mu];
    const SIndex& uiSiteN_p_mu_m_nu = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiN_p_mu_m_nu];

    deviceSU3 ret(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_m_nu__nu, byFieldId));
    ret.DaggerMul(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_m_nu__mu, byFieldId));
    ret.Mul(_deviceS4(byFieldId, pDeviceData, sSite, uiBigIndex, mu, nu, rho));

    ret.MulReal(_deviceHi(sCenter,
        __deviceSiteIndexToInt4(uiSiteN_p_mu.m_uiSiteIndex),
        __deviceSiteIndexToInt4(uiSiteN_p_mu_m_nu.m_uiSiteIndex),
        uiSiteN_p_mu, uiSiteN_p_mu_m_nu, i));

    return ret;
}

/**
* [h(n+mu) + h(n+mu+nu)] U(n) T1 U(n+nu)
* mu mu, + -
*
*/
static __device__ __inline__ deviceSU3 _deviceStapleT1(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    const SSmallInt4 n_p_mu = _deviceSmallInt4OffsetC(sSite, __fwd(mu));
    const SSmallInt4 n_p_nu = _deviceSmallInt4OffsetC(sSite, __fwd(nu));
    const SSmallInt4 n_p_mu_p_nu = _deviceSmallInt4OffsetC(n_p_mu, __fwd(nu));

    const UINT uiN_p_mu = __bi(n_p_mu);
    const UINT uiN_p_mu_p_nu = __bi(n_p_mu_p_nu);

    const SIndex& n__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][uiBigIndex * _DC_Dir + mu];
    const SIndex& n_p_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_nu) + mu];

    const SIndex& uiSiteN_p_mu = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiN_p_mu];
    const SIndex& uiSiteN_p_mu_p_nu = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiN_p_mu_p_nu];

    deviceSU3 ret(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n__mu, byFieldId));
    ret.Mul(_deviceT1(byFieldId, pDeviceData, sSite, uiBigIndex, mu, nu, rho));
    ret.MulDagger(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_p_nu__mu, byFieldId));

    ret.MulReal(_deviceHi(sCenter,
        __deviceSiteIndexToInt4(uiSiteN_p_mu.m_uiSiteIndex),
        __deviceSiteIndexToInt4(uiSiteN_p_mu_p_nu.m_uiSiteIndex),
        uiSiteN_p_mu, uiSiteN_p_mu_p_nu, i));

    return ret;
}

/**
* [h(n-mu) + h(n-mu+nu)] U(n-mu) T2 U(n+nu-mu)
* mu mu, - +
*
*/
static __device__ __inline__ deviceSU3 _deviceStapleT2(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    const SSmallInt4 n_m_mu = _deviceSmallInt4OffsetC(sSite, __bck(mu));
    const SSmallInt4 n_m_mu_p_nu = _deviceSmallInt4OffsetC(n_m_mu, __fwd(nu));

    const UINT uiN_m_mu = __bi(n_m_mu);
    const UINT uiN_m_mu_p_nu = __bi(n_m_mu_p_nu);

    const SIndex& n_m_mu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][uiN_m_mu * _DC_Dir + mu];
    const SIndex& n_m_mu_p_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][uiN_m_mu_p_nu * _DC_Dir + mu];

    const SIndex& uiSiteN_m_mu = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiN_m_mu];
    const SIndex& uiSiteN_m_mu_p_nu = __idx->m_pDeviceIndexPositionToSIndex[byFieldId][uiN_m_mu_p_nu];

    deviceSU3 ret(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_m_mu__mu, byFieldId));
    ret.DaggerMul(_deviceT2(byFieldId, pDeviceData, sSite, uiBigIndex, mu, nu, rho));
    ret.Mul(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_m_mu_p_nu__mu, byFieldId));

    ret.MulReal(_deviceHi(sCenter,
        __deviceSiteIndexToInt4(uiSiteN_m_mu.m_uiSiteIndex),
        __deviceSiteIndexToInt4(uiSiteN_m_mu_p_nu.m_uiSiteIndex),
        uiSiteN_m_mu, uiSiteN_m_mu_p_nu, i));

    return ret;
}

/**
* i = 0, 1, 2 for coefficient
* _deviceChairTerm1,2,3 for partial mu, nu, rho
* For partial mu, the staple is (1/8)(s1+s2+s3+s4)
*/
static __device__ __inline__ deviceSU3 _deviceStapleChairTerm1(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    deviceSU3 ret(_deviceStapleS1(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, mu, nu, rho, i));
    ret.Add(_deviceStapleS2(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, mu, nu, rho, i));
    ret.Add(_deviceStapleS3(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, mu, nu, rho, i));
    ret.Add(_deviceStapleS4(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, mu, nu, rho, i));
    return ret;
}

/**
* i = 0, 1, 2 for coefficient
* _deviceChairTerm1,2,3 for partial mu, nu, rho
* It is (1/8) * (T1+T2 + T1(mu<->rho) + T2(mu<->rho))
*/
static __device__ __inline__ deviceSU3 _deviceStapleChairTerm2(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    deviceSU3 ret(_deviceStapleT1(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, mu, nu, rho, i));
    ret.Add(_deviceStapleT2(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, mu, nu, rho, i));
    ret.Add(_deviceStapleT1(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, rho, nu, mu, i));
    ret.Add(_deviceStapleT2(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, rho, nu, mu, i));
    return ret;
}

#pragma endregion

#pragma endregion

#pragma region Projective plane related

#pragma region Chair

//=============================
//The shifted coord should be conflict with Dirichlet, so we do not consider it
//This is for projective plane
static __device__ __inline__ Real _deviceSiteCoeff(
    SSmallInt4 sSite4, const SSmallInt4& sCenterSite, BYTE byFieldId, BYTE byType)
{
    if (0 == byType)
    {
        //x
        const UBOOL bOpposite = sSite4.x >= static_cast<SBYTE>(_DC_Lx) || sSite4.x < 0;
        sSite4 = __deviceSiteIndexToInt4(__idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(sSite4)].m_uiSiteIndex);
        if (bOpposite)
        {
            return -sSite4.x + sCenterSite.x - F(0.5);
        }
        return sSite4.x - sCenterSite.x + F(0.5);
    }
    if (1 == byType)
    {
        //y
        const UBOOL bOpposite = sSite4.y >= static_cast<SBYTE>(_DC_Ly) || sSite4.y < 0;
        sSite4 = __deviceSiteIndexToInt4(__idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(sSite4)].m_uiSiteIndex);
        if (bOpposite)
        {
            return sSite4.y - sCenterSite.y + F(0.5);
        }
        return -sSite4.y + sCenterSite.y - F(0.5);
    }
    if (3 == byType)
    {
        //There should be NO byType = 3?
        sSite4 = __deviceSiteIndexToInt4(__idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(sSite4)].m_uiSiteIndex);
        return -sSite4.y + sCenterSite.y - F(0.5);
    }

    //byType = 2 and this is XY
    const BYTE bOppositeX = (sSite4.x >= static_cast<SBYTE>(_DC_Lx) || sSite4.x < 0) ? 1 : 0;
    const BYTE bOppositeY = (sSite4.y >= static_cast<SBYTE>(_DC_Ly) || sSite4.y < 0) ? 1 : 0;
    sSite4 = __deviceSiteIndexToInt4(__idx->m_pDeviceIndexPositionToSIndex[byFieldId][__bi(sSite4)].m_uiSiteIndex);
    const Real fRet = (sSite4.x - sCenterSite.x + F(0.5)) * (sSite4.y - sCenterSite.y + F(0.5));
    if (0 != (bOppositeX ^ bOppositeY))
    {
        return -fRet;
    }
    return fRet;
}

static __device__ __inline__ Real _deviceHiShifted(
    BYTE byFieldId,
    const SSmallInt4& center,
    SSmallInt4 site, SSmallInt4 site2, BYTE i)
{
    return _deviceSiteCoeff(site, center, byFieldId, i) + _deviceSiteCoeff(site2, center, byFieldId, i);
}


static __device__ __inline__ deviceSU3 _deviceStapleS1Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    const SSmallInt4 n_p_mu = _deviceSmallInt4OffsetC(sSite, mu + 1);
    const SSmallInt4 n_p_nu = _deviceSmallInt4OffsetC(sSite, nu + 1);

    const SIndex& n_p_mu__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_mu) + nu];
    const SIndex& n_p_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_nu) + mu];

    deviceSU3 ret(_deviceS1(byFieldId, pDeviceData, sSite, uiBigIndex, mu, nu, rho));
    ret.Mul(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_p_nu__mu, byFieldId));
    ret.MulDagger(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_p_mu__nu, byFieldId));

    ret.MulReal(_deviceHiShifted(byFieldId, sCenter, sSite, n_p_nu, i));

    return ret;
}

static __device__ __inline__ deviceSU3 _deviceStapleS2Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    const SSmallInt4 n_m_nu = _deviceSmallInt4OffsetC(sSite, __bck(nu));
    const SSmallInt4 n_m_nu_p_mu = _deviceSmallInt4OffsetC(n_m_nu, __fwd(mu));
    const SIndex& n_m_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_nu) + mu];
    const SIndex& n_m_nu_p_mu__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_nu_p_mu) + nu];

    deviceSU3 ret(_deviceS2(byFieldId, pDeviceData, sSite, uiBigIndex, mu, nu, rho));
    ret.Mul(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_m_nu__mu, byFieldId));
    ret.Mul(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_m_nu_p_mu__nu, byFieldId));

    ret.MulReal(_deviceHiShifted(byFieldId, sCenter, sSite, n_m_nu, i));

    return ret;
}

static __device__ __inline__ deviceSU3 _deviceStapleS3Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    const SSmallInt4 n_p_mu = _deviceSmallInt4OffsetC(sSite, __fwd(mu));
    const SSmallInt4 n_p_mu_p_nu = _deviceSmallInt4OffsetC(n_p_mu, __fwd(nu));
    const SSmallInt4 n_p_nu = _deviceSmallInt4OffsetC(sSite, __fwd(nu));

    const SIndex& n__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][uiBigIndex * _DC_Dir + nu];
    const SIndex& n_p_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_nu) + mu];

    deviceSU3 ret(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n__nu, byFieldId));
    ret.Mul(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_p_nu__mu, byFieldId));
    ret.Mul(_deviceS3(byFieldId, pDeviceData, sSite, uiBigIndex, mu, nu, rho));

    ret.MulReal(_deviceHiShifted(byFieldId, sCenter, n_p_mu, n_p_mu_p_nu, i));

    return ret;

}

static __device__ __inline__ deviceSU3 _deviceStapleS4Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    const SSmallInt4 n_p_mu = _deviceSmallInt4OffsetC(sSite, __fwd(mu));
    const SSmallInt4 n_p_mu_m_nu = _deviceSmallInt4OffsetC(n_p_mu, __bck(nu));
    const SSmallInt4 n_m_nu = _deviceSmallInt4OffsetC(sSite, __bck(nu));

    const UINT n_m_nu_bi4 = __bi4(n_m_nu);

    const SIndex& n_m_nu__nu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_nu_bi4 + nu];
    const SIndex& n_m_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][n_m_nu_bi4 + mu];

    deviceSU3 ret(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_m_nu__nu, byFieldId));
    ret.DaggerMul(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_m_nu__mu, byFieldId));
    ret.Mul(_deviceS4(byFieldId, pDeviceData, sSite, uiBigIndex, mu, nu, rho));

    ret.MulReal(_deviceHiShifted(byFieldId, sCenter, n_p_mu, n_p_mu_m_nu, i));

    return ret;
}

static __device__ __inline__ deviceSU3 _deviceStapleT1Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    const SSmallInt4 n_p_mu = _deviceSmallInt4OffsetC(sSite, __fwd(mu));
    const SSmallInt4 n_p_nu = _deviceSmallInt4OffsetC(sSite, __fwd(nu));
    const SSmallInt4 n_p_mu_p_nu = _deviceSmallInt4OffsetC(n_p_mu, __fwd(nu));

    const SIndex& n__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][uiBigIndex * _DC_Dir + mu];
    const SIndex& n_p_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_p_nu) + mu];

    deviceSU3 ret(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n__mu, byFieldId));
    ret.Mul(_deviceT1(byFieldId, pDeviceData, sSite, uiBigIndex, mu, nu, rho));
    ret.MulDagger(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_p_nu__mu, byFieldId));

    ret.MulReal(_deviceHiShifted(byFieldId, sCenter, n_p_mu, n_p_mu_p_nu, i));

    return ret;
}

static __device__ __inline__ deviceSU3 _deviceStapleT2Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    const SSmallInt4 n_m_mu = _deviceSmallInt4OffsetC(sSite, __bck(mu));
    const SSmallInt4 n_m_mu_p_nu = _deviceSmallInt4OffsetC(n_m_mu, __fwd(nu));

    const SIndex& n_m_mu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_mu) + mu];
    const SIndex& n_m_mu_p_nu__mu = __idx->m_pDeviceIndexLinkToSIndex[byFieldId][__bi4(n_m_mu_p_nu) + mu];

    deviceSU3 ret(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_m_mu__mu, byFieldId));
    ret.DaggerMul(_deviceT2(byFieldId, pDeviceData, sSite, uiBigIndex, mu, nu, rho));
    ret.Mul(_deviceGetGaugeBCSU3DirSIndex(pDeviceData, n_m_mu_p_nu__mu, byFieldId));

    ret.MulReal(_deviceHiShifted(byFieldId, sCenter, n_m_mu, n_m_mu_p_nu, i));

    return ret;
}

static __device__ __inline__ deviceSU3 _deviceStapleChairTerm1Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    deviceSU3 ret(_deviceStapleS1Shifted(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, mu, nu, rho, i));
    ret.Add(_deviceStapleS2Shifted(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, mu, nu, rho, i));
    ret.Add(_deviceStapleS3Shifted(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, mu, nu, rho, i));
    ret.Add(_deviceStapleS4Shifted(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, mu, nu, rho, i));
    return ret;
}

static __device__ __inline__ deviceSU3 _deviceStapleChairTerm2Shifted(
    BYTE byFieldId,
    const deviceSU3* __restrict__ pDeviceData,
    const SSmallInt4& sCenter, const SSmallInt4& sSite, UINT uiSiteIndex,
    UINT uiBigIndex, BYTE mu, BYTE nu, BYTE rho, BYTE i)
{
    deviceSU3 ret(_deviceStapleT1Shifted(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, mu, nu, rho, i));
    ret.Add(_deviceStapleT2Shifted(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, mu, nu, rho, i));
    ret.Add(_deviceStapleT1Shifted(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, rho, nu, mu, i));
    ret.Add(_deviceStapleT2Shifted(byFieldId, pDeviceData, sCenter, sSite, uiSiteIndex, uiBigIndex, rho, nu, mu, i));
    return ret;
}

#pragma endregion

#pragma endregion

#pragma endregion

__END_NAMESPACE

#endif //#ifndef _CACTIONGAUGEPLAQUETTE_ROTATING_H_

//=============================================================================
// END OF FILE
//=============================================================================