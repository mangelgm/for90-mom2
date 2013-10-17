! MODULE: diffr
! AUTHOR: Jouni Makitalo
! DESCRIPTION:
! Routines for computing diffracted power in periodic problems.
MODULE diffr
  USE source
  USE nfields
  USE common

  IMPLICIT NONE

  INTEGER, PARAMETER :: max_prdsrc = 4
  INTEGER, PARAMETER :: fresnel_nquad = 25

CONTAINS
  FUNCTION Gpff(r, rp, k, prd) RESULT(g)
    REAL (KIND=dp), DIMENSION(3), INTENT(IN) :: r, rp
    TYPE(prdnfo), POINTER, INTENT(IN) :: prd
    COMPLEX (KIND=dp), INTENT(IN) :: k
    COMPLEX (KIND=dp) :: g

    INTEGER :: i, j
    REAL (KIND=dp), DIMENSION(2) :: kt
    COMPLEX (KIND=dp) :: kz, phasor
    REAL (KIND=dp) :: sgn, A
    INTEGER, PARAMETER :: max_orders = 0

    IF(r(3)>rp(3)) THEN
       sgn = 1.0_dp
    ELSE
       sgn = -1.0_dp
    END IF

    g = 0.0_dp

    DO i=-max_orders,max_orders
       DO j=-max_orders,max_orders
          
          ! Lattice vector.
          kt = (/prd%coef(prd%cwl)%k0x + 2.0_dp*PI*(i/(prd%dx*prd%cp)&
               - j*prd%sp/(prd%dy*prd%cp)) ,&
               prd%coef(prd%cwl)%k0y + 2.0_dp*PI*j/prd%dy/)
          
          ! Skip evanescent waves.
          IF(REAL(k**2,KIND=dp)<dotr(kt,kt)) THEN
             CYCLE
          END IF
          
          kz = SQRT(k**2 - dotr(kt,kt))

          phasor = EXP((0,1)*dotr(kt,r(1:2)))*EXP(-(0,1)*dotr(kt,rp(1:2)))*&
               EXP(sgn*(0,1)*kz*r(3))*EXP(-sgn*(0,1)*kz*rp(3))

          g = g + phasor/kz
       END DO
    END DO

    A = prd%dx*prd%dy*prd%cp

    g = g*(0,1)/(2*A)
  END FUNCTION Gpff

  FUNCTION gradGpff(r, rp, k, prd) RESULT(gg)
    REAL (KIND=dp), DIMENSION(3), INTENT(IN) :: r, rp
    TYPE(prdnfo), POINTER, INTENT(IN) :: prd
    COMPLEX (KIND=dp), INTENT(IN) :: k
    COMPLEX (KIND=dp), DIMENSION(3) :: gg

    INTEGER :: i, j
    REAL (KIND=dp), DIMENSION(2) :: kt
    COMPLEX (KIND=dp) :: kz, phasor
    REAL (KIND=dp) :: sgn, A
    INTEGER, PARAMETER :: max_orders = 0

    IF(r(3)>rp(3)) THEN
       sgn = 1.0_dp
    ELSE
       sgn = -1.0_dp
    END IF

    gg(:) = 0.0_dp

    DO i=-max_orders,max_orders
       DO j=-max_orders,max_orders
          
          ! Lattice vector.
          kt = (/prd%coef(prd%cwl)%k0x + 2.0_dp*PI*(i/(prd%dx*prd%cp)&
               - j*prd%sp/(prd%dy*prd%cp)) ,&
               prd%coef(prd%cwl)%k0y + 2.0_dp*PI*j/prd%dy/)
          
          ! Skip evanescent waves.
          IF(REAL(k**2,KIND=dp)<dotr(kt,kt)) THEN
             CYCLE
          END IF
          
          kz = SQRT(k**2 - dotr(kt,kt))

          phasor = EXP((0,1)*dotr(kt,r(1:2)))*EXP(-(0,1)*dotr(kt,rp(1:2)))*&
               EXP(sgn*(0,1)*kz*r(3))*EXP(-sgn*(0,1)*kz*rp(3))

          gg(1:2) = gg(1:2) + kt*phasor/kz
          gg(3) = gg(3) + sgn*phasor
       END DO
    END DO

    A = prd%dx*prd%dy*prd%cp

    gg(:) = gg(:)/(2*A)
  END FUNCTION gradGpff

  SUBROUTINE diff_fields(mesh, ga, nf, x, nedgestot, omega, ri, prd, r, e, h)
    TYPE(mesh_container), INTENT(IN) :: mesh
    COMPLEX (KIND=dp), INTENT(IN) :: ri
    REAL (KIND=dp), INTENT(IN) :: omega
    TYPE(group_action), DIMENSION(:), INTENT(IN) :: ga
    INTEGER, INTENT(IN) :: nf, nedgestot
    TYPE(prdnfo), POINTER, INTENT(IN) :: prd
    COMPLEX (KIND=dp), DIMENSION(:), INTENT(IN) :: x
    REAL (KIND=dp), DIMENSION(3), INTENT(IN) :: r

    COMPLEX (KIND=dp), DIMENSION(3), INTENT(INOUT) :: e, h

    REAL (KIND=dp), DIMENSION(3,SIZE(qw)) :: qpn
    INTEGER :: n, q, t, edgeind
    COMPLEX (KIND=dp) :: c1, c2, g, k
    COMPLEX (KIND=dp), DIMENSION(3) :: gg
    REAL (KIND=dp), DIMENSION(3) :: divfn
    REAL (KIND=dp), DIMENSION(3,SIZE(qw),3) :: fv
    REAL (KIND=dp) :: An

    k = ri*omega/c0    
    c1 = (0,1)*omega*mu0
    c2 = (0,1)*omega*(ri**2)*eps0

    e(:) = 0.0_dp
    h(:) = 0.0_dp

    DO n=1,mesh%nfaces
       An = mesh%faces(n)%area
       qpn = GLquad_points(n, mesh)

       DO q=1,3
          CALL vrwg(qpn(:,:),n,q,mesh,fv(:,:,q))
          divfn(q) = rwgDiv(n,q,mesh)
       END DO

       DO t=1,SIZE(qw)
          g = Gpff(r, qpn(:,t), k, prd)
          gg = gradGpff(r, qpn(:,t), k, prd)

          DO q=1,3
             edgeind = mesh%faces(n)%edge_indices(q)
             edgeind = mesh%edges(edgeind)%parent_index

             e = e + qw(t)*An*( c1*g*fv(:,t,q)*x(edgeind) + gg*divfn(q)*x(edgeind)/c2 +&
                  crossc(gg, CMPLX(fv(:,t,q),KIND=dp))*x(edgeind + nedgestot) )

             h = h + qw(t)*An*( c2*g*fv(:,t,q)*x(edgeind + nedgestot) +&
                  gg*divfn(q)*x(edgeind + nedgestot)/c1 -&
                  crossc(gg, CMPLX(fv(:,t,q),KIND=dp))*x(edgeind) )
          END DO
       END DO
    END DO
  END SUBROUTINE diff_fields

  FUNCTION diff_irradiance(mesh, ga, addsrc, src, x, nedgestot, omega, ri, ri_inc, prd) RESULT(irr)
    TYPE(mesh_container), INTENT(IN) :: mesh
    LOGICAL, INTENT(IN) :: addsrc
    TYPE(srcdata), INTENT(IN) :: src
    COMPLEX (KIND=dp), INTENT(IN) :: ri, ri_inc
    REAL (KIND=dp), INTENT(IN) :: omega
    TYPE(group_action), DIMENSION(:), INTENT(IN) :: ga
    INTEGER, INTENT(IN) :: nedgestot
    TYPE(prdnfo), POINTER, INTENT(IN) :: prd
    COMPLEX (KIND=dp), DIMENSION(:,:), INTENT(IN) :: x

    REAL (KIND=dp) :: irr, pinc, eval_dist, k
    INTEGER :: nf
    REAL (KIND=dp), DIMENSION(3) :: dir
    COMPLEX (KIND=dp), DIMENSION(3) :: e, h, einc, hinc
    REAL (KIND=dp), DIMENSION(2) :: kt

    nf = 1

    ! Field evaluation distance. Arbitrary positive value.
    ! For good numerical accuracy, should be on the order of
    ! wavelength.
    eval_dist = 1e-6

    !dir = get_dir(pwtheta, pwphi)

    k = REAL(ri,KIND=dp)*omega/c0
    kt = (/prd%coef(prd%cwl)%k0x, prd%coef(prd%cwl)%k0y/)
    dir = (/kt(1), kt(2), -SQRT(k**2 - dotr(kt,kt))/)

    dir = dir/normr(dir)

    CALL diff_fields(mesh, ga, nf, x(:,nf), nedgestot, omega, ri, prd, dir*eval_dist, e, h)

    IF(addsrc) THEN
       CALL src_fields(src, omega, ri, dir*eval_dist, einc, hinc)
       
       e = e + einc
       h = h + hinc
    END IF

    pinc = REAL(ri_inc,KIND=dp)/(c0*mu0)
    
    ! The relative irradiance diffracted to 0th order in the given domain.
    irr = dotr(REAL(crossc(e, CONJG(h)), KIND=dp), dir)/pinc

  END FUNCTION diff_irradiance

  FUNCTION diffracted_power(b, wlindex, dindex, r0, xorder, yorder) RESULT(power)
    TYPE(batch), INTENT(IN) :: b
    INTEGER, INTENT(IN) :: wlindex, dindex, xorder, yorder
    REAL (KIND=dp), DIMENSION(3), INTENT(IN) :: r0

    REAL (KIND=dp) :: power, wl, omega
    REAL (KIND=dp), DIMENSION(:), ALLOCATABLE :: qwx, ptx, qwy, pty
    COMPLEX (KIND=dp), DIMENSION(3) :: e, h, einc, hinc, auxe, auxh, gg
    COMPLEX (KIND=dp), DIMENSION(6) :: ff
    COMPLEX (KIND=dp) :: ri, ri1, k
    REAL (KIND=dp), DIMENSION(3) :: pt
    REAL (KIND=dp) :: irrinc, hdx, hdy, pinc, sgn
    INTEGER :: n, m, nx, ny
    REAL (KIND=dp), DIMENSION(3) :: xaxis, yaxis, dir
    TYPE(prdnfo), POINTER :: prd

    prd => b%prd(b%domains(dindex)%gf_index)

    wl = b%sols(wlindex)%wl
    omega = 2.0_dp*pi*c0/wl
    ri = b%media(b%domains(dindex)%medium_index)%prop(wlindex)%ri
    ri1 = b%media(b%domains(1)%medium_index)%prop(wlindex)%ri

    ! Wavenumber in diffraction medium.
    k = ri*omega/c0

    ! Direction of incident plane-wave (and thus 0th order transmission).
    dir = get_dir(prd%pwtheta, prd%pwphi)

    ! Select the number of integration points based on wavelength and period.
    !nx = NINT(prd%dx/b%sols(wlindex)%wl*20)
    !ny = NINT(prd%dy/b%sols(wlindex)%wl*20)
    nx = 51
    ny = 51

    ! Minus one if transmission to segative half-plane z<0.
    sgn = -1.0_dp

    ! Make sure that the numbers are odd.
    IF(MOD(nx,2)==0) THEN
       nx = nx + 1
    END IF

    IF(MOD(ny,2)==0) THEN
       ny = ny + 1
    END IF

    ALLOCATE(qwx(1:nx), ptx(1:nx), qwy(1:ny), pty(1:ny))

    hdx = prd%dx*0.5_dp
    hdy = prd%dy*0.5_dp

    xaxis = (/prd%cp, prd%sp, 0.0_dp/)
    yaxis = (/0.0_dp, 1.0_dp, 0.0_dp/)

    ! Compute weights and nodes from Simpson's rule.
    CALL get_simpsons_weights(-hdx, hdx, nx-1, qwx)
    CALL get_simpsons_points(-hdx, hdx, nx-1, ptx)
    CALL get_simpsons_weights(-hdy, hdy, ny-1, qwy)
    CALL get_simpsons_points(-hdy, hdy, ny-1, pty)

    ff(:) = 0.0_dp

    !$OMP PARALLEL DEFAULT(NONE)&
    !$OMP SHARED(nx,ny,prd,r0,xaxis,ptx,yaxis,pty,dindex,b,wlindex,qwx,qwy,ff,omega,ri,dir,wl,sgn,k)&
    !$OMP PRIVATE(m,n,pt,e,h,einc,hinc,gg,auxe,auxh)
    !$OMP DO REDUCTION(+:ff) SCHEDULE(STATIC)
    DO m=1,ny
       DO n=1,nx

          pt = r0 + xaxis*ptx(n) + yaxis*pty(m)
          
          CALL scat_fields(b%domains(dindex)%mesh, b%ga, b%sols(wlindex)%x, b%mesh%nedges,&
               omega, ri, prd, pt, e, h)

          IF(dindex==1) THEN
             CALL src_fields(b%src, omega, ri, pt, einc, hinc)

             e = e + einc
             h = h + hinc
          END IF

          gg = gradGpff(r0 + dir*wl, pt, k, prd)

          auxe = sgn*crossc(gg, (/e(2), -e(1), (0.0_dp,0.0_dp)/))
          auxh = sgn*crossc(gg, (/h(2), -h(1), (0.0_dp,0.0_dp)/))

          ff = ff + 2.0_dp*qwx(n)*qwy(m)*(/auxe(:), auxh(:)/)
       END DO
    END DO
    !$OMP END DO
    !$OMP END PARALLEL
        
    ! cp is the Jacobian of the area integration.
    ff = ff*prd%cp

    pinc = REAL(ri1,KIND=dp)/(c0*mu0)
    
    ! The relative power diffracted to 0th order in the given domain.
    ! power = (ABS(eff(1))**2 + ABS(eff(2))**2)*ri/ri1
    power = dotr(REAL(crossc(ff(1:3), CONJG(ff(4:6))), KIND=dp), dir)/pinc
    !power = -REAL(ff(1)*CONJG(ff(4)) - ff(2)*CONJG(ff(3)), KIND=dp)/pinc

    DEALLOCATE(qwx, ptx, qwy, pty)

  END FUNCTION diffracted_power
END MODULE diffr
