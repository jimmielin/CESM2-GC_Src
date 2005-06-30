! $Id: gcap_convect_mod.f,v 1.1 2005/06/22 20:50:03 bmy Exp $
      MODULE GCAP_CONVECT_MOD
!
!******************************************************************************
!  Module GCAP_CONVECT_MOD contains routines (originally from GISS) which
!  perform shallow and deep convection for the GCAP met fields.  This module
!  was based on FVDAS_CONVECT_MOD. (swu, bmy, 6/9/05)
!  
!  Module Variables:
!  ============================================================================
!  (1 ) GRAV     (REAL*8 ) : Gravitational constant [m/s2]
!  (2 ) SMALLEST (REAL*8 ) : The smallest double-precision number 
!  (3 ) TINYNUM  (REAL*8 ) : 2 times the machine epsilon for dble-precision
!
!  Module Routines:
!  ============================================================================
!  (1 ) INIT_GCAP_CONVECT  : Initializes fvDAS convection scheme
!  (2 ) GCAP_CONVECT       : GCAP/GISS convection driver
!  (4 ) ARCCONVTRAN        : Sets up fields for ZHANG/MCFARLANE convection
!  (5 ) CONVTRAN           : ZHANG/MCFARLANE convection scheme routine
!  (6 ) WHENFGT            : Test funtion
!
!  GEOS-CHEM modules referenced by fvdas_convect_mod.f:
!  ============================================================================
!  (1 ) pressure_mod.f     : Module containing routines to compute P(I,J,L)
!
!  NOTES:  
!******************************************************************************
!  
      IMPLICIT NONE
      
      !=================================================================
      ! MODULE PRIVATE DECLARATIONS -- keep certain internal variables 
      ! and routines from being seen outside "gcap_convect_mod.f"
      !=================================================================

      ! Declare everything PRIVATE ...
      PRIVATE
      
      ! ... except these routines
      PUBLIC :: GCAP_CONVECT

      !=================================================================
      ! MODULE VARIABLES
      !=================================================================

      ! Constants
      REAL*8,  PARAMETER :: GRAV     = 9.8d0
      REAL*8,  PARAMETER :: SMALLEST = TINY(1D0)
      REAL*8,  PARAMETER :: TINYNUM  = 2*EPSILON(1D0)

      !=================================================================
      ! MODULE ROUTINES -- follow below the "CONTAINS" statement 
      !=================================================================
      CONTAINS

!------------------------------------------------------------------------------

      SUBROUTINE GCAP_CONVECT( TDT,    Q,      NTRACE,   DP,   
     &                         NSTEP,  FRACIS, TCVV,     INDEXSOL, 
     &                         UPDE,   DNDE,   ENTRAIN,  DETRAINE, 
     &                         UPDN,   DNDN,   DETRAINN ) 
!
!******************************************************************************
!  Subroutine GCAP_CONVECT is the convection driver routine for GEOS-4/fvDAS
!  met fields.  It calls both HACK and ZHANG/MCFARLANE convection schemes.
!  (swu, bmy, 6/9/05)
!
!  Arguments as Input:
!  ============================================================================
!  (1 ) TDT    (REAL*8 ) : 2 * delta-T                          [s]
!  (2 ) Q      (REAL*8 ) : Array of transported tracers         [v/v]
!  (3 ) RPDEL  (REAL*8 ) : 1./pde                               [1/hPa]
!  (4 ) ETA    (REAL*8 ) : GMAO Hack convective mass flux       [kg/m2/s]
!  (5 ) BETA   (REAL*8 ) : GMAO Hack overshoot parameter        [unitless]
!  (6 ) NTRACE (INTEGER) : Number of tracers to transport       [unitless]
!  (7 ) MU     (REAL*8 ) : GMAO updraft mass flux   (ZMMU)      [ ]pa/s
!  (8 ) MD     (REAL*8 ) : GMAO downdraft mass flux (ZMMD)      [ ]pa/s
!  (9 ) EU     (REAL*8 ) : GMAO updraft entrainment (ZMEU)      [ ]pa/s
!  (10) DP     (REAL*8 ) : Delta-pressure between level edges   [hPa]pa
!  (11) NSTEP  (INTEGER) : Time step index                      [unitless]
!  (12) FRACIS (REAL*8 ) : Fraction of tracer that is insoluble [unitless]
!
!  Arguments as Output:
!  ============================================================================
!  (2 ) Q      (REAL*8 ) : Modified tracer array              [v/v]
! 
!  Important Local Variables:
!  ============================================================================
!  (1 ) IDEEP  (INTEGER)  : Gathering array
!  (2 ) IL1G   (INTEGER)  : Gathered min lon indices over which to operate
!  (3 ) IL2G   (INTEGER)  : Gathered max lon indices over which to operate
!  (4 ) JT     (INTEGER)  : Index of cloud top for each column
!  (5 ) LENGATH(INTEGER)  : ??       
!  (6 ) DSUBCLD(REAL*8 )  : Delta pressure from cloud base to sfc
!  (7 ) DPG    (REAL*8 )  : gathered .01*dp
!  (8 ) MX     (INTEGER)  : Index of cloud top for each column
!
!  NOTES:
!******************************************************************************
!

#     include "CMN_SIZE"      ! Size parameters

      ! Arguments
      INTEGER, INTENT(IN)    :: NSTEP, NTRACE             
      INTEGER, INTENT(IN)    :: INDEXSOL(NTRACE) 
      REAL*8,  INTENT(IN)    :: TDT                
      REAL*8,  INTENT(INOUT) :: Q(IIPAR,JJPAR,LLPAR,NTRACE)          
      REAL*8,  INTENT(IN)    :: DP(IIPAR,JJPAR,LLPAR)     
      REAL*8,  INTENT(IN)    :: FRACIS(IIPAR,JJPAR,LLPAR,NTRACE) 
      REAL*8,  INTENT(IN)    :: TCVV(NTRACE)
      REAL*8,  INTENT(IN)    :: UPDE(IIPAR,JJPAR,LLPAR)     
      REAL*8,  INTENT(IN)    :: DNDE(IIPAR,JJPAR,LLPAR)     
      REAL*8,  INTENT(IN)    :: ENTRAIN(IIPAR,JJPAR,LLPAR)
      REAL*8,  INTENT(IN)    :: DETRAINE(IIPAR,JJPAR,LLPAR)
      REAL*8,  INTENT(IN)    :: UPDN(IIPAR,JJPAR,LLPAR)     
      REAL*8,  INTENT(IN)    :: DNDN(IIPAR,JJPAR,LLPAR)     
      REAL*8,  INTENT(IN)    :: DETRAINN(IIPAR,JJPAR,LLPAR)

      ! Local variables
      INTEGER                :: J, I, L, N
      INTEGER                :: JT(IIPAR)
      INTEGER                :: MX(IIPAR)
      INTEGER                :: IDEEP(IIPAR)
      INTEGER                :: IL1G=1
      INTEGER                :: IL2G=JJPAR
      INTEGER                :: LENGATH, istep
      REAL*8                 :: QTMP(IIPAR,LLPAR,NTRACE)
      REAL*8                 :: FTMP(IIPAR,LLPAR,NTRACE)
      REAL*8                 :: DPG(IIPAR,LLPAR)
      REAL*8                 :: ED(IIPAR,LLPAR)
      REAL*8                 :: UPDEG(IIPAR,LLPAR)
      REAL*8                 :: DNDEG(IIPAR,LLPAR)
      REAL*8                 :: ENTRAING(IIPAR,LLPAR)
      REAL*8                 :: DETRAINEG(IIPAR,LLPAR)
      REAL*8                 :: TOTALDNDEG(IIPAR,LLPAR)
      REAL*8                 :: UPDNG(IIPAR,LLPAR)
      REAL*8                 :: DNDNG(IIPAR,LLPAR)
      REAL*8                 :: DETRAINNG(IIPAR,LLPAR)
      REAL*8                 :: TOTALDNDNG(IIPAR,LLPAR)
      REAL*8                 :: ENTRAINN(IIPAR,LLPAR)
      REAL*8                 :: ENTRAINNG(IIPAR,LLPAR)

      !=================================================================
      ! GCAP_CONVECT begins here!
      !=================================================================

      ! Fake entrainment in non-entraining plumes (swu, bmy, 6/9/05)
      ENTRAINN(:,:) = 0d0

      ! Loop over latitudes
!$OMP PARALLEL DO
!$OMP+DEFAULT( SHARED )
!$OMP+PRIVATE( I,         J,          L,      N,     QTMP      )      
!$OMP+PRIVATE( FTMP,      ISTEP,      UPDEG,  DNDEG, DETRAINEG )
!$OMP+PRIVATE( ENTRAING,  TOTALDNDEG, DPG,    JT,    MX        )
!$OMP+PRIVATE( IDEEP,     LENGATH,    UPDNG,  DNDNG, DETRAINNG )
!$OMP+PRIVATE( ENTRAINNG, TOTALDNDNG                           )
!$OMP+SCHEDULE( DYNAMIC )
      DO J = 1, JJPAR
         
         ! Save latitude slice of STT into Q
         DO N = 1, NTRACE
         DO L = 1, LLPAR
         DO I = 1, IIPAR
            QTMP(I,L,N) = Q(I,J,L,N)
            FTMP(I,L,N) = FRACIS(I,J,L,N)
         ENDDO
         ENDDO
         ENDDO

         !----------------------------
         ! Entraining convection
         !---------------------------- 

         ! Set up convection fields
         CALL ARCONVTRAN( NSTEP,        DP(:,J,:),       UPDE(:,J,:),
     &                    DNDE(:,J,:),  DETRAINE(:,J,:), ENTRAIN(:,J,:),   
     &                    UPDEG,        DNDEG,           DETRAINEG, 
     &                    ENTRAING,     TOTALDNDEG,      DPG,           
     &                    JT,           MX,              IDEEP, 
     &                    LENGATH   )

         ! Internal convection steps
         DO ISTEP = 1, NSTEP 

            ! Do the convection
            CALL CONVTRAN( QTMP,        NTRACE,          UPDEG,  
     &                     DNDEG,       DETRAINEG,       ENTRAING,         
     &                     TOTALDNDEG,  DPG,             JT,          
     &                     MX,          IDEEP,           
     &                     1,           LENGATH,         NSTEP,
     &                     0.5D0*TDT,   FTMP,            TCVV,        
     &                     INDEXSOL,    J ) 

         ENDDO 

         !----------------------------
         ! Non-entraining convection
         !---------------------------- 

         ! Set up convection fields
         CALL ARCONVTRAN( NSTEP,        DP(:,J,:),       UPDN(:,J,:),
     &                    DNDN(:,J,:),  DETRAINN(:,J,:), ENTRAINN(:,:),   
     &                    UPDNG,        DNDNG,           DETRAINNG,  
     &                    ENTRAINNG,    TOTALDNDNG,      DPG,           
     &                    JT,           MX,              IDEEP, 
     &                    LENGATH   )

         ! Loop over internal convection timesteps
         DO ISTEP = 1, NSTEP  

            ! Do the convection
            CALL CONVTRAN( QTMP,        NTRACE,          UPDNG,  
     &                     DNDNG,       DETRAINNG,       ENTRAINNG,         
     &                     TOTALDNDNG,  DPG,              
     &                     JT,          MX,              IDEEP, 
     &                     1,           LENGATH,         NSTEP, 
     &                     0.5D0*TDT,   FTMP,            TCVV,        
     &                     INDEXSOL,    J ) 

         ENDDO

         ! Store latitude slice back into STT
         DO N = 1, NTRACE
         DO L = 1, LLPAR
         DO I = 1, IIPAR
            Q(I,J,L,N) = QTMP(I,L,N) 
         ENDDO
         ENDDO
         ENDDO
      ENDDO 
!$OMP END PARALLEL DO

      ! Return to calling program
      END SUBROUTINE GCAP_CONVECT

!------------------------------------------------------------------------------

      SUBROUTINE ARCONVTRAN( NSTEP, DP,  MU,       MD, 
     &                       DU,    EU,  MUG,      MDG,   
     &                       DUG,   EUG, TOTALMDG, DPG,   
     &                       JTG,   JBG, IDEEP,    LENGATH )
!
!******************************************************************************
!  Subroutine ARCONVTRAN sets up the convective transport using archived mass
!  fluxes from the ZHANG/MCFARLANE convection scheme.  The setup involves:
!    (1) Gather mass flux arrays.
!    (2) Calc the mass fluxes that are determined by mass balance.
!    (3) Determine top and bottom of convection.
!  (pjr, dsa, bmy, 6/26/03)
!
!  Arguments as Input:
!  ============================================================================
!  (1 ) NSTEP   (INTEGER) : Time step index
!  (2 ) DP      (REAL*8 ) : Delta pressure between interfaces [Pa]     Pa
!  (3 ) MU      (REAL*8 ) : Mass flux up                      [kg/m2/s]Pa/s
!  (4 ) MD      (REAL*8 ) : Mass flux down                    [kg/m2/s]Pa/s
!  (5 ) EU      (REAL*8 ) : Mass entraining from updraft      [1/s]    Pa/s
!
!  Arguments as Output:
!  ============================================================================
!  (6 ) MUG     (REAL*8 ) : Gathered mu                                Pa/s
!  (7 ) MDG     (REAL*8 ) : Gathered md                                Pa/s
!  (8 ) DUG     (REAL*8 ) : Mass detraining from updraft (gathered)    Pa/S
!  (9 ) EUG     (REAL*8 ) : Gathered eu                                Pa/S
!  (10) EDG     (REAL*8 ) : Mass entraining from downdraft (gathered)  Pa/s
!  (11) DPG     (REAL*8 ) : Gathered                                   Pa
!  (12) DSUBCLD (REAL*8 ) : Delta pressure from cloud base to sfc (gathered)
!  (13) JTG     (INTEGER) : ??
!  (14) JBG     (INTEGER) : ??
!  (15) IDEEP   (INTEGER) : ??
!  (16) LENGATH (INTEGER) : ??
!
!  NOTES:
!******************************************************************************
!
#     include "CMN_SIZE" ! Size parameters
      
      ! Arguments
      INTEGER, INTENT(IN)  :: NSTEP
      INTEGER, INTENT(OUT) :: JTG(IIPAR)
      INTEGER, INTENT(OUT) :: JBG(IIPAR)
      INTEGER, INTENT(OUT) :: IDEEP(IIPAR)
      INTEGER, INTENT(OUT) :: LENGATH
      REAL*8,  INTENT(IN)  :: DP(IIPAR,LLPAR) 
      REAL*8,  INTENT(IN)  :: MU(IIPAR,LLPAR)
      REAL*8,  INTENT(IN)  :: MD(IIPAR,LLPAR)
      REAL*8,  INTENT(IN)  :: DU(IIPAR,LLPAR)
      REAL*8,  INTENT(IN)  :: EU(IIPAR,LLPAR) 
      REAL*8,  INTENT(OUT) :: MUG(IIPAR,LLPAR)
      REAL*8,  INTENT(OUT) :: MDG(IIPAR,LLPAR)
      REAL*8,  INTENT(OUT) :: DUG(IIPAR,LLPAR)      
      REAL*8,  INTENT(OUT) :: EUG(IIPAR,LLPAR)
      REAL*8,  INTENT(OUT) :: totalMDG(IIPAR,LLPAR)
      REAL*8,  INTENT(OUT) :: DPG(IIPAR,LLPAR)

      ! Local variables
      INTEGER              :: I, K, LENPOS 
      INTEGER              :: INDEX(IIPAR)
      REAL*8               :: SUM(IIPAR)
      REAL*8               :: RDPG(IIPAR,LLPAR)      
      REAL*8               :: TOTALMD(IIPAR,LLPAR)

      !=================================================================
      ! ARCONVTRAN begins here!
      !=================================================================

      ! Gathered array contains all columns with a updraft.
      DO I = 1, IIPAR
         SUM(I) = 0.d0
      ENDDO

      DO K = 1, LLPAR
      DO I = 1, IIPAR
         SUM(I) = SUM(I) + MU(I,K)

         ! Calculate totalMD --- all the downdrafts coming downstairs
         IF ( K == 1 ) THEN 
            TOTALMD(I,K) = MD(I,K)
         ELSE 
            TOTALMD(I,K) = TOTALMD(I,K-1) + MD(I,K)
         Endif

      ENDDO
      ENDDO

      CALL WHENFGT( IIPAR, SUM, 1, 0D0, IDEEP, LENGATH )

      ! Return if LENGATH is zero
      IF ( LENGATH == 0 ) return

      !=================================================================
      ! Gather input mass fluxes
      !=================================================================
      DO K = 1, LLPAR
      DO I = 1, LENGATH
         DPG(I,K)      = DP(IDEEP(I),K)    !Pa
         MUG(I,K)      = MU(IDEEP(I),K)    !Pa/s
         MDG(I,K)      = MD(IDEEP(I),K) 
         EUG(I,K)      = EU(IDEEP(I),K)    
         DUG(I,K)      = DU(IDEEP(I),K) 
         TOTALMDG(I,K) = TOTALMD(IDEEP(I),K) !!!=sum( MD(ideep(I),1:K) )
      ENDDO
      ENDDO

      !=================================================================
      ! Find top and bottom layers with updrafts.
      !=================================================================
      DO I = 1, LENGATH
         JTG(I) = LLPAR
         JBG(I) = 1
      ENDDO

      DO K = 2, LLPAR
         
         CALL WHENFGT( LENGATH, MUG(:,K), 1, 0D0, INDEX, LENPOS )
         
         DO I = 1, LENPOS    
            JTG(INDEX(I)) = MIN( K-1, JTG(INDEX(I)) )
            JBG(INDEX(I)) = MAX( K, JBG(INDEX(I)) )
         ENDDO
      ENDDO

      ! Return to calling program
      END SUBROUTINE ARCONVTRAN

!------------------------------------------------------------------------------

      SUBROUTINE CONVTRAN( Q,    NTRACE,   MU,         MD,       
     &                     DU,   EU,       TOTALMD,    DP,    
     &                     JT,   MX,       IDEEP,      IL1G,     
     &                     IL2G, NSTEP,    DELT,       FRACIS, 
     &                     TCVV, INDEXSOL, LATI_INDEX ) 
!
!******************************************************************************
!  Subroutine CONVTRAN applies the convective transport of trace species
!  (assuming moist mixing ratio) using the ZHANG/MCFARLANE convection scheme. 
!  (swu, bmy, 6/9/05)
!
!  Arguments as Input:
!  ============================================================================
!  (1 ) Q       (REAL*8 ) : Tracer concentrations including moisture [v/v]
!  (2 ) NTRACE  (INTEGER) : Number of tracers to transport           [unitless]
!  (3 ) MU      (REAL*8 ) : Mass flux up                             Pa/s
!  (4 ) MD      (REAL*8 ) : Mass flux down                           Pa/s
!  (5 ) DU      (REAL*8 ) : Mass detraining from updraft             Pa/s
!  (6 ) EU      (REAL*8 ) : Mass entraining from updraft             Pa/s
!  (7 ) ED      (REAL*8 ) : Mass entraining from downdraft           Pa/s
!  (8 ) DP      (REAL*8 ) : Delta pressure between interfaces        Pa
!  (9 ) DSUBCLD (REAL*8 ) : Delta pressure from cloud base to sfc
!  (10) JT      (INTEGER) : Index of cloud top for each column
!  (11) MX      (INTEGER) : Index of cloud top for each column
!  (12) IDEEP   (INTEGER) : Gathering array
!  (13) IL1G    (INTEGER) : Gathered min lon indices over which to operate
!  (14) IL2G    (INTEGER) : Gathered max lon indices over which to operate
!  (15) NSTEP   (INTEGER) : Time step index
!  (16) DELT    (REAL*8 ) : Time step
!  (17) FRACIS  (REAL*8 ) : Fraction of tracer that is insoluble
!
!  Arguments as Output:
!  ============================================================================
!  (1 ) Q       (REAL*8 ) : Contains modified tracer mixing ratios [v/v]
!
!  Important Local Variables:
!  ============================================================================
!  (1 ) CABV    (REAL*8 ) : Mixing ratio of constituent above
!  (2 ) CBEL    (REAL*8 ) : Mix ratio of constituent beloqw
!  (3 ) CDIFR   (REAL*8 ) : Normalized diff between cabv and cbel
!  (4 ) CHAT    (REAL*8 ) : Mix ratio in env at interfaces
!  (5 ) CMIX    (REAL*8 ) : Gathered tracer array 
!  (6 ) COND    (REAL*8 ) : Mix ratio in downdraft at interfaces
!  (7 ) CONU    (REAL*8 ) : Mix ratio in updraft at interfaces
!  (8 ) DCONDT  (REAL*8 ) : Gathered tend array 
!  (9 ) FISG    (REAL*8 ) : gathered insoluble fraction of tracer
!  (10) KBM     (INTEGER) : Highest altitude index of cloud base [unitless]
!  (11) KTM     (INTEGER) : Hightet altitude index of cloud top  [unitless]
!  (12) MBSTH   (REAL*8 ) : Threshold for mass fluxes
!  (13) SMALL   (REAL*8 ) : A small number
!
!  NOTES:
!******************************************************************************
!
      ! References to F90 modules
      USE DIAG_MOD,     ONLY : AD38, CONVFLUP
      USE GRID_MOD,     ONLY : GET_AREA_M2
      USE DAO_MOD,      ONLY : AD
      USE PRESSURE_MOD, ONLY : GET_PEDGE

#     include "CMN_SIZE"     ! Size parameters
#     include "CMN_DIAG" 
  
      ! Arguments
      INTEGER, INTENT(IN)    :: NTRACE             
      INTEGER, INTENT(IN)    :: JT(IIPAR)          
      INTEGER, INTENT(IN)    :: MX(IIPAR)          
      INTEGER, INTENT(IN)    :: IDEEP(IIPAR)       
      INTEGER, INTENT(IN)    :: IL1G               
      INTEGER, INTENT(IN)    :: IL2G               
      INTEGER, INTENT(IN)    :: NSTEP               
      INTEGER, INTENT(IN)    :: INDEXSOL(NTRACE)
      INTEGER, INTENT(IN)    :: LATI_INDEX
      REAL*8,  INTENT(INOUT) :: Q(IIPAR,LLPAR,NTRACE)  
      REAL*8,  INTENT(IN)    :: MU(IIPAR,LLPAR)      
      REAL*8,  INTENT(IN)    :: MD(IIPAR,LLPAR)      
      REAL*8,  INTENT(IN)    :: DU(IIPAR,LLPAR)      
      REAL*8,  INTENT(IN)    :: EU(IIPAR,LLPAR)      
      REAL*8,  INTENT(IN)    :: totalMD(IIPAR,LLPAR)      
      REAL*8,  INTENT(IN)    :: DP(IIPAR,LLPAR)      
      REAL*8,  INTENT(IN)    :: DELT                
      REAL*8,  INTENT(IN)    :: FRACIS(IIPAR,LLPAR,NTRACE) 
      REAL*8,  INTENT(IN)    :: TCVV(NTRACE)

      ! Local variables
      INTEGER                :: I,     K,      KBM,     KK,     KKP1
      INTEGER                :: KM1,   KP1,    KTM,     M,  istep
      INTEGER                :: II,    JJ,     LL,      NN
      REAL*8                 :: CABV,  CBEL,   CDIFR,   CD2,    DENOM
      REAL*8                 :: SMALL, MBSTH,  MUPDUDP, MINC,   MAXC
      REAL*8                 :: QN,    FLUXIN, FLUXOUT, NETFLUX             
      REAL*8                 :: CHAT(IIPAR,LLPAR)     
      REAL*8                 :: COND(IIPAR,LLPAR)     
      REAL*8                 :: CMIX(IIPAR,LLPAR)     
      REAL*8                 :: FISG(IIPAR,LLPAR)     
      REAL*8                 :: CONU(IIPAR,LLPAR)     
      REAL*8                 :: DCONDT(IIPAR,LLPAR)   
      REAL*8                 :: AREA_M2,        DELTAP
      REAL*8                 :: TRC_BFCONVTRAN, TRC_AFCONVTRAN
      REAL*8                 :: PLUMEIN, PLUMEOUT, PLUMECHANGE

      !=================================================================
      ! CONVTRAN begins here!
      !=================================================================

      ! A small number
      SMALL = 1.d-36

      ! Threshold below which we treat the mass fluxes as zero (in mb/s)
      MBSTH = 1.d-15

      !=================================================================
      ! Find the highest level top and bottom levels of convection
      !=================================================================
      KTM = LLPAR
      KBM = LLPAR
      DO I = IL1G, IL2G
         KTM = MIN( KTM, JT(I) )
         KBM = MIN( KBM, MX(I) )
      ENDDO

      ! Loop ever each tracer
      DO M = 1, NTRACE

         ! Gather up the tracer and set tend to zero
         DO K = 1,    LLPAR
         DO I = IL1G, IL2G
            CMIX(I,K) = Q(IDEEP(I),K,M)
            FISG(I,K) = FRACIS(IDEEP(I),K,M)
         ENDDO
         ENDDO

         !==============================================================
         ! From now on work only with gathered data
         ! Interpolate environment tracer values to interfaces
         !==============================================================
         DO K = 1, LLPAR
            KM1 = MAX(1,K-1)

            DO I = IL1G, IL2G
               MINC = MIN( CMIX(I,KM1), CMIX(I,K) )
               MAXC = MAX( CMIX(I,KM1), CMIX(I,K) )

               IF ( MINC < 0 ) THEN 
                  CDIFR = 0.D0
               ELSE
                  CDIFR = ABS( CMIX(I,K)-CMIX(I,KM1) ) / MAX(MAXC,SMALL)
               ENDIF

               IF ( CDIFR > 1.D-6 ) THEN

                  ! If the two layers differ significantly.
                  ! use a geometric averaging procedure
                  CABV = MAX( CMIX(I,KM1), MAXC*TINYNUM, SMALLEST )
                  CBEL = MAX( CMIX(I,K),   MAXC*TINYNUM, SMALLEST )

                  CHAT(I,K) = LOG( CABV / CBEL)
     &                       /   ( CABV - CBEL)
     &                       *     CABV * CBEL

               ELSE             

                  ! Small diff, so just arithmetic mean
                  CHAT(I,K) = 0.5d0 * ( CMIX(I,K) + CMIX(I,KM1) )
               ENDIF

               ! Provisional up and down draft values
               CONU(I,K) = CHAT(I,K)
               COND(I,K) = CHAT(I,K)

               ! Provisional tends
               DCONDT(I,K) = 0.d0
            ENDDO
         ENDDO

         !==============================================================
         ! Do levels adjacent to top and bottom
         !==============================================================
         K   = 2
         KM1 = 1
         KK  = LLPAR 

         DO I = IL1G, IL2G
            PLUMEIN = MU(I,KK)

            IF ( PLUMEIN > MBSTH ) THEN
                CONU(I,KK) = CMIX(I,KK) 
            ENDIF

            IF ( MD(I,K) < -MBSTH ) THEN
                COND(I,K) = 0.5d0 * ( CMIX(I,KM1) + CONU(I,KM1) )
            ENDIF
         ENDDO
         
         !==============================================================
         ! Updraft from bottom to top
         !==============================================================
         DO KK = LLPAR-1,1,-1
            KKP1 = MIN( LLPAR, KK+1 )

            DO I = IL1G, IL2G
               PLUMEIN     = MU(I,KKP1) + EU(I,KK) 
               PLUMEOUT    = MU(I,KK) + DU(I,KK) - 0.5D0*MD(I,KK)
               PLUMECHANGE = PLUMEOUT - PLUMEIN

               IF ( PLUMECHANGE > MBSTH ) THEN
                  IF ( PLUMEOUT > MBSTH ) THEN
                     CONU(I,KK) = (MU(I,KKP1)*CONU(I,KKP1) *FISG(I,KK)
     &                          + EU(I,KK)*CMIX(I,KK)
     &                          + PLUMECHANGE*CMIX(I,KK)  )
     &                          / PLUMEOUT
                  ENDIF   
                  
               ELSE
                  IF ( PLUMEIN > MBSTH ) THEN
                     CONU(I,KK) = ( MU(I,KKP1)*CONU(I,KKP1) *FISG(I,KK)
     &                          + EU(I,KK)*CMIX(I,KK) )
     &                          / PLUMEIN
                  ENDIF
               ENDIF

               IF ( CONU(I,KK) < 0.0D0 ) THEN
                  WRITE(6,*) 'Warning! negative conu!!!', conu(I,KK)
                  CALL FLUSH(6)
               !Else if ( conu(i,KK) > 1.0e-10 ) then
               !    write(6,*) 'Warning! Too big conu!!!', conu(I,KK)
               !    call flush(6)
               ENDIF
            ENDDO
         ENDDO

         !==============================================================
         ! Downdraft from top to bottom
         !==============================================================
         DO K = 3, LLPAR
            KM1 = MAX( 1, K-1 )

            DO I = IL1G, IL2G
               IF ( TOTALMD(I,K) < -MBSTH ) THEN
                  IF ( MD(I,K) < -MBSTH ) THEN
                     COND(I,K) = ( TOTALMD(I,KM1)*COND(I,KM1) 
     $                  + 0.5D0 * MD(I,K) * ( CMIX(I,K)+CONU(I,K) ))
     $                  / TOTALMD(I,K)
                  ELSE
                     COND(I,K) = COND(I,KM1)
                  ENDIF
               ENDIF
               
               IF ( COND(I,K) < 0.0D0 ) THEN
                  WRITE(6,*) 'WARNING! negative cond!!!', cond(I,K)
                  CALL FLUSH(6)
                !Else if ( cond(i,K) > 1.0e-10 ) then
                !   write(6,*) 'Warning! Too big cond!!!', cond(I,K)
                !   call flush(6)
               ENDIF
            ENDDO
         ENDDO

         DO K = 1, LLPAR
            KM1 = MAX( 1,     K-1 )
            KP1 = MIN( LLPAR, K+1 )
            
            DO I = IL1G, IL2G

               ! Version 3 limit fluxes outside convection to mass in 
               ! appropriate layer.  These limiters are probably only safe
               ! for positive definite quantitities.  It assumes that mu 
               ! and md already satify a courant number limit of 1

!               FLUXIN =  MU(I,KP1)* CONU(I,KP1) * FISG(I,K)
!     $                + (MU(I,K)+ totalMD(I,K)) * CMIX(I,KM1) 
!     $                -  totalMD(I,K)  * COND(I,K)
!   
!              FLUXOUT =  MU(I,K)   * CONU(I,K)     
!     $                + (MU(I,KP1)+ totalMD(I,KP1))*CMIX(I,K)
!     $                 - totalMD(I,KP1) * COND(I,KP1) 

               IF ( K == LLPAR ) THEN

                  FLUXIN  = MU(I,K)        * CMIX(I,KM1)              
     &                    - TOTALMD(I,KM1) * COND(I,KM1)

                  FLUXOUT = MU(I,K)        * CONU(I,K) 
     &                    - TOTALMD(I,KM1) * CMIX(I,K)

               ELSE
           
                  FLUXIN  =  MU(I,KP1)      * CONU(I,KP1) * FISG(I,K)
     &                    +  MU(I,K)        * CMIX(I,KM1) 
     &                    -  TOTALMD(I,KM1) * COND(I,KM1)
     &                    -  TOTALMD(I,K)   * CMIX(I,KP1) * FISG(I,K)
   
                  FLUXOUT = MU(I,K)        * CONU(I,K)     
     &                    + MU(I,KP1)      * CMIX(I,K)
     &                    - TOTALMD(I,K)   * COND(I,K) 
     &                    - TOTALMD(I,KM1) * CMIX(I,K)
               ENDIF

!!!!!!!!!!!!!!!!!!backup: also works OK !!!!!!!!!!!!!!!!!!!!!!!
!              FLUXIN =  MU(I,KP1)* CONU(I,KP1) 
!     $                +  MU(I,K)  * 0.5d0*(CHAT(I,K)+CMIX(I,KM1)) 
!     $                -  MD(I,K)  * COND(I,K)   
!     $                -  MD(I,KP1)* 0.5d0*(CHAT(I,KP1)+CMIX(I,KP1))
!
!               FLUXOUT = MU(I,K)   * CONU(I,K)     
!     $                 + MU(I,KP1) * 0.5d0*(CHAT(I,KP1)+CMIX(I,K))
!     $                 - MD(I,KP1) * COND(I,KP1) 
!     $                 - MD(I,K)   * 0.5d0*(CHAT(I,K)+CMIX(I,K))
!
!               FLUXIN =  MU(I,KP1)* CONU(I,KP1) 
!     $                +  MU(I,K)  * CHAT(I,K)
!     $                -  MD(I,K)  * COND(I,K)   
!     $                -  MD(I,KP1)* CHAT(I,KP1)
!
!               FLUXOUT = MU(I,K)   * CONU(I,K)     
!     $                 + MU(I,KP1) * CHAT(I,KP1)
!     $                 - MD(I,KP1) * COND(I,KP1) 
!     $                 - MD(I,K)   * CHAT(I,K)
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

               !==================================================
               ! ND38 Diagnostic: loss of soluble tracer to wet
               ! scavenging in cloud updrafts [kg/s].  
               !==================================================
               NN = INDEXSOL(M)

               IF ( ND38 > 0 .and. NN > 0 ) THEN
 
                  ! Grid box indices 
                  II = IDEEP(I)
                  JJ = LATI_INDEX
                  LL = LLPAR - K + 1

                  ! Grid box surface area [m2] 
                  AREA_M2 = GET_AREA_M2( JJ ) 

                  ! Save into AD38 array [kg/s]
                  AD38(II,JJ,LL,NN) = AD38(II,JJ,LL,NN) 
     &                 +  MU(I,KP1)    * AREA_M2 / GRAV * CONU(I,KP1) 
     &                 * (1-FISG(I,K)) / TCVV(M) / FLOAT(NSTEP) 
     &                 -  TOTALMD(I,K) * AREA_M2 / GRAV * CMIX(I,KP1) 
     &                 * (1-FISG(I,K)) / TCVV(M) / FLOAT(NSTEP)
               ENDIF

               IF ( ND14 > 0 ) THEN 
                  II = IDEEP (I)
                  JJ = LATI_INDEX
                  LL = LLPAR - K + 1
                  
                  ! Grid box surface area [m2]
                  AREA_M2 = GET_AREA_M2( jj ) 

                  CONVFLUP(II,JJ,LL,M) = CONVFLUP(II,JJ,LL,M)  
     &              + MU(I,K) * AREA_M2  * (CONU(I,K)-CMIX(I,KM1))
     &              / GRAV / TCVV(M) / FLOAT(NSTEP)
     &              - TOTALMD(I,KM1) * AREA_M2 * (CMIX(I,K)-COND(I,KM1)) 
     &              / GRAV / TCVV(M) / FLOAT(NSTEP)
                  
               ENDIF 

               NETFLUX = FLUXIN - FLUXOUT

            ! Prior to 6/9/05:
            ! We don't need this for GCAP (bmy, 6/9/05)
            !IF ( ABS(NETFLUX) < MAX(FLUXIN,FLUXOUT)*TINYNUM) THEN
            !   NETFLUX = 0.D0
            !ENDIF

               IF ( DP(I,K)< 0.0D0 ) THEN 
                  WRITE(6,*) 'WARNING! negative DP!!!', DP(I,K)
                  CALL FLUSH(6)
               ENDIF


               DCONDT(I,K)= NETFLUX/DP(I,K) !AD(IDEEP(I),lati_index,llpar+1-k)
            ENDDO               !I
         Enddo                  !K


         DO K = KBM, LLPAR             
            KM1 = MAX( 1, K-1 )
            
            DO I = IL1G, IL2G

              !!!temp diag ATTENTION HERE!!!!

               IF ( K == (MX(I) + 100000) ) THEN
                  
                  FLUXIN  =(MU(I,K)+MD(I,K))* CMIX(I,KM1)              
     $                    - MD(I,K)*COND(I,K)

                  FLUXOUT = MU(I,K)*CONU(I,K) 

!!!!!!!!!!!!!!!!!!!!!!BACK UP; also works well !!!!!!!!!!!!!!!!!!!!!
!                  FLUXIN  = MU(I,K)*0.5d0*(CHAT(I,K)+CMIX(I,KM1))
!     $                    - MD(I,K)*COND(I,K)
!
!                  FLUXOUT = MU(I,K)*CONU(I,K) 
!     $                    - MD(I,K)*0.5d0*(CHAT(I,K)+CMIX(I,K))
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!


                  NETFLUX = FLUXIN - FLUXOUT

                  IF (ABS(NETFLUX).LT.MAX(FLUXIN,FLUXOUT)*TINYNUM) THEN
                     NETFLUX = 0.d0
                  ENDIF
                  
                  DCONDT(I,K) = NETFLUX / DP(I,K)
                  
               ELSE IF ( K > MX(I) ) THEN

                  !!!!DCONDT(I,K) = 0.D0

               ENDIF

            ENDDO  !I
         ENDDO     !K

         !==============================================================
         ! Update and scatter data back to full arrays
         !==============================================================
         DO K = 1, LLPAR
            KP1 = MIN( LLPAR, K+1 )
            DO I = IL1G, IL2G    
            
               QN = CMIX(I,K) + DCONDT(I,K) * DELT 

               ! Do not make Q negative!!!
               IF ( QN < 0d0 ) then
                  QN = 0D0
               ENDIF            

               Q(IDEEP(I),K,M) = QN
            ENDDO   
         ENDDO      
         
      ENDDO   ! End of tracer loop

      ! Return to calling program
      END SUBROUTINE CONVTRAN

!-----------------------------------------------------------------------------

      SUBROUTINE WHENFGT( N, ARRAY, INC, TARGET, INDEX, NVAL )
!
!******************************************************************************
!  Subroutine WHENFGT is a
!
!  Arguments as Input:
!  ============================================================================
!  
!******************************************************************************
!
      ! Arguments
      INTEGER :: INDEX(*), NVAL, INC, N
      REAL*8  :: ARRAY(*), TARGET

      ! Local variables
      INTEGER :: I, INA

      !=================================================================
      ! WHENFGT begins here!
      !=================================================================
      INA  = 1
      NVAL = 0

      IF ( INC < 0 ) INA = (-INC)*(N-1)+1

      DO I = 1, N
         IF ( ARRAY(INA) > TARGET ) THEN
	    NVAL        = NVAL+1
	    INDEX(NVAL) = I
         ENDIF
         INA = INA + INC
      ENDDO

      ! Return to calling program
      END SUBROUTINE WHENFGT

!------------------------------------------------------------------------------

      END MODULE GCAP_CONVECT_MOD