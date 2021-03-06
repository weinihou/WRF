      SUBROUTINE MSGWRT(LUNIT,MESG,MGBYT)

C$$$  SUBPROGRAM DOCUMENTATION BLOCK
C
C SUBPROGRAM:    MSGWRT
C   PRGMMR: WOOLLEN          ORG: NP20       DATE: 1994-01-06
C
C ABSTRACT: THIS SUBROUTINE PERFORMS SOME FINAL CHECKS ON AN OUTPUT
C  BUFR MESSAGE (E.G., CONFIRMING THAT EACH SECTION OF THE MESSAGE HAS
C  AN EVEN NUMBER OF BYTES WHEN NECESSARY, "STANDARDIZING" THE MESSAGE
C  IF REQUESTED VIA A PREVIOUS CALL TO BUFR ARCHIVE LIBRARY SUBROUTINE
C  STDMSG, ETC.), AND THEN PREPARES THE MESSAGE FOR FINAL OUTPUT TO
C  LOGICAL UNIT LUNIT (E.G., ADDING THE STRING "7777" TO THE LAST FOUR
C  BYTES OF THE MESSAGE, APPENDING ZEROED-OUT BYTES UP TO A SUBSEQUENT
C  MACHINE WORD BOUNDARY, ETC.).  IT THEN WRITES OUT THE FINISHED
C  MESSAGE TO LOGICAL UNIT LUNIT AND ALSO STORES A COPY OF IT WITHIN
C  COMMON /BUFRMG/ FOR POSSIBLE LATER RETRIEVAL VIA BUFR ARCHIVE
C  LIBRARY SUBROUTINE WRITSA.
C
C PROGRAM HISTORY LOG:
C 1994-01-06  J. WOOLLEN -- ORIGINAL AUTHOR
C 1997-07-29  J. WOOLLEN -- MODIFIED TO UPDATE THE CURRENT BUFR VERSION
C                           WRITTEN IN SECTION 0 FROM 2 TO 3
C 1998-07-08  J. WOOLLEN -- REPLACED CALL TO CRAY LIBRARY ROUTINE
C                           "ABORT" WITH CALL TO NEW INTERNAL BUFRLIB
C                           ROUTINE "BORT"
C 1998-11-24  J. WOOLLEN -- MODIFIED TO ZERO OUT THE PADDING BYTES
C                           WRITTEN AT THE END OF SECTION 4
C 2000-09-19  J. WOOLLEN -- MAXIMUM MESSAGE LENGTH INCREASED FROM
C                           10,000 TO 20,000 BYTES
C 2003-11-04  J. ATOR    -- DON'T WRITE TO LUNIT IF OPENED AS A NULL
C                           FILE BY OPENBF {NULL(LUN) = 1 IN NEW
C                           COMMON BLOCK /NULBFR/} (WAS IN DECODER
C                           VERSION); ADDED DOCUMENTATION
C 2003-11-04  S. BENDER  -- ADDED REMARKS/BUFRLIB ROUTINE
C                           INTERDEPENDENCIES
C 2003-11-04  D. KEYSER  -- UNIFIED/PORTABLE FOR WRF; ADDED HISTORY
C                           DOCUMENTATION; OUTPUTS MORE COMPLETE
C                           DIAGNOSTIC INFO WHEN ROUTINE TERMINATES
C                           ABNORMALLY
C 2004-08-18  J. ATOR    -- IMPROVED DOCUMENTATION; ADDED LOGIC TO CALL
C                           STNDRD IF REQUESTED VIA COMMON /MSGSTD/;
C                           ADDED LOGIC TO CALL OVRBS1 IF NECESSARY;
C                           MAXIMUM MESSAGE LENGTH INCREASED FROM
C                           20,000 TO 50,000 BYTES
C 2005-11-29  J. ATOR    -- USE GETLENS, IUPBS01, PADMSG, PKBS1 AND
C                           NMWRD; ADDED LOGIC TO CALL PKBS1 AND/OR
C                           CNVED4 WHEN NECESSARY
C 2009-03-23  J. ATOR    -- USE IDXMSG AND ERRWRT; ADD CALL TO ATRCPT;
C                           ALLOW STANDARDIZING VIA COMMON /MSGSTD/
C                           EVEN IF DATA IS COMPRESSED; WORK ON LOCAL
C                           COPY OF INPUT MESSAGE
C 2012-09-15  J. WOOLLEN -- MODIFIED FOR C/I/O/BUFR INTERFACE;
C                           CALL NEW ROUTINE BLOCKS FOR FILE BLOCKING
C                           AND NEW C ROUTINE CWRBUFR TO WRITE BUFR
C                           MESSAGE TO DISK FILE
C
C USAGE:    CALL MSGWRT (LUNIT, MESG, MGBYT)
C   INPUT ARGUMENT LIST:
C     LUNIT    - INTEGER: FORTRAN LOGICAL UNIT NUMBER FOR BUFR FILE
C     MESG     - INTEGER: *-WORD PACKED BINARY ARRAY CONTAINING BUFR
C                MESSAGE TO OUTPUT TO LUNIT
C     MGBYT    - INTEGER: LENGTH OF BUFR MESSAGE IN BYTES
C
C   OUTPUT FILES:
C     UNIT "LUNIT" - BUFR FILE
C
C REMARKS:
C    THIS ROUTINE CALLS:        ATRCPT   BORT     CNVED4   ERRWRT
C                               GETLENS  IDXMSG   IUPB     IUPBS01
C                               NMWRD    PADMSG   PKB      PKBS1
C                               PKC      STATUS   STNDRD   BLOCKS
C                               CWRBUFR
C    THIS ROUTINE IS CALLED BY: CLOSMG   COPYBF   COPYMG   CPYMEM
C                               CPYUPD   MSGUPD   WRCMPS   WRDXTB
C                               Normally not called by any application
C                               programs.
C
C ATTRIBUTES:
C   LANGUAGE: FORTRAN 77
C   MACHINE:  PORTABLE TO ALL PLATFORMS
C
C$$$

      INCLUDE 'bufrlib.prm'

      PARAMETER (MXCOD=15)

      COMMON /BUFRMG/ MSGLEN,MSGTXT(MXMSGLD4)
      COMMON /NULBFR/ NULL(NFILES)
      COMMON /QUIET / IPRT
      COMMON /MSGSTD/ CSMF
      COMMON /S01CM/  NS01V,CMNEM(MXS01V),IVMNEM(MXS01V)
      COMMON /TNKRCP/ ITRYR,ITRMO,ITRDY,ITRHR,ITRMI,CTRT

      CHARACTER*128 ERRSTR

      CHARACTER*8 CMNEM
      CHARACTER*4 BUFR,SEVN
      CHARACTER*1 CSMF
      CHARACTER*1 CTRT
      DIMENSION   MESG(*)
      DIMENSION   MBAY(MXMSGLD4),MSGNEW(MXMSGLD4)
      DIMENSION   IEC0(2)

      DATA BUFR/'BUFR'/
      DATA SEVN/'7777'/

C-----------------------------------------------------------------------
C-----------------------------------------------------------------------

C     MAKE A LOCAL COPY OF THE INPUT MESSAGE FOR USE WITHIN THIS
C     SUBROUTINE, SINCE CALLS TO ANY OR ALL OF THE SUBROUTINES STNDRD,
C     CNVED4, PKBS1, ATRCPT, ETC. MAY END UP MODIFYING THE MESSAGE
C     BEFORE IT FINALLY GETS WRITTEN OUT TO LUNIT.

      MBYT = MGBYT

      IEC0(1) = MESG(1)
      IEC0(2) = MESG(2)
      IBIT = 32
      CALL PKB(MBYT,24,IEC0,IBIT)

      DO II = 1, NMWRD(IEC0)
        MBAY(II) = MESG(II)
      ENDDO

C     OVERWRITE ANY VALUES WITHIN SECTION 0 OR SECTION 1 THAT WERE
C     REQUESTED VIA PREVIOUS CALLS TO BUFR ARCHIVE LIBRARY SUBROUTINE
C     PKVS01.  IF A REQUEST WAS MADE TO CHANGE THE BUFR EDITION NUMBER
C     TO 4, THEN ACTUALLY CONVERT THE MESSAGE AS WELL.

      IF(NS01V.GT.0) THEN
        DO I=1,NS01V
          IF(CMNEM(I).EQ.'BEN') THEN
            IF(IVMNEM(I).EQ.4) THEN

C             INSTALL SECTION 0 BYTE COUNT FOR USE BY SUBROUTINE CNVED4.

              IBIT = 32
              CALL PKB(MBYT,24,MBAY,IBIT)

              CALL CNVED4(MBAY,MXMSGLD4,MSGNEW)

C             COMPUTE MBYT FOR THE NEW EDITION 4 MESSAGE.

              MBYT = IUPBS01(MSGNEW,'LENM')

C             COPY THE MSGNEW ARRAY BACK INTO MBAY.

              DO II = 1, NMWRD(MSGNEW)
                MBAY(II) = MSGNEW(II)
              ENDDO
            ENDIF
          ELSE

C           OVERWRITE THE REQUESTED VALUE.

            CALL PKBS1(IVMNEM(I),MBAY,CMNEM(I))
          ENDIF
        ENDDO
      ENDIF

C     "STANDARDIZE" THE MESSAGE IF REQUESTED VIA COMMON /MSGSTD/.
C     HOWEVER, WE DO NOT WANT TO DO THIS IF THE MESSAGE CONTAINS BUFR
C     TABLE (DX) INFORMATION, IN WHICH CASE IT IS ALREADY "STANDARD".

      IF ( ( CSMF.EQ.'Y' ) .AND. ( IDXMSG(MBAY).NE.1 ) )  THEN

C       INSTALL SECTION 0 BYTE COUNT AND SECTION 5 '7777' INTO THE
C       ORIGINAL MESSAGE.  THIS IS NECESSARY BECAUSE SUBROUTINE STNDRD
C       REQUIRES A COMPLETE AND WELL-FORMED BUFR MESSAGE AS ITS INPUT.

        IBIT = 32
        CALL PKB(MBYT,24,MBAY,IBIT)
        IBIT = (MBYT-4)*8
        CALL PKC(SEVN,4,MBAY,IBIT)

        CALL STNDRD(LUNIT,MBAY,MXMSGLD4,MSGNEW)

C       COMPUTE MBYT FOR THE NEW "STANDARDIZED" MESSAGE.

        MBYT = IUPBS01(MSGNEW,'LENM')

C       COPY THE MSGNEW ARRAY BACK INTO MBAY.

        DO II = 1, NMWRD(MSGNEW)
          MBAY(II) = MSGNEW(II)
        ENDDO
      ENDIF

C     APPEND THE TANK RECEIPT TIME TO SECTION 1 IF REQUESTED VIA
C     COMMON /TNKRCP/, UNLESS THE MESSAGE CONTAINS BUFR TABLE (DX)
C     INFORMATION. 

      IF ( ( CTRT.EQ.'Y' ) .AND. ( IDXMSG(MBAY).NE.1 ) ) THEN

C       INSTALL SECTION 0 BYTE COUNT FOR USE BY SUBROUTINE ATRCPT.

        IBIT = 32
        CALL PKB(MBYT,24,MBAY,IBIT)

        CALL ATRCPT(MBAY,MXMSGLD4,MSGNEW)

C       COMPUTE MBYT FOR THE REVISED MESSAGE.

        MBYT = IUPBS01(MSGNEW,'LENM')

C       COPY THE MSGNEW ARRAY BACK INTO MBAY.

        DO II = 1, NMWRD(MSGNEW)
          MBAY(II) = MSGNEW(II)
        ENDDO
      ENDIF

C     GET THE SECTION LENGTHS.

      CALL GETLENS(MBAY,4,LEN0,LEN1,LEN2,LEN3,LEN4,L5)

C     DEPENDING ON THE EDITION NUMBER OF THE MESSAGE, WE NEED TO ENSURE
C     THAT EACH SECTION WITHIN THE MESSAGE HAS AN EVEN NUMBER OF BYTES.

      IF(IUPBS01(MBAY,'BEN').LT.4) THEN
        IF(MOD(LEN1,2).NE.0) GOTO 901
        IF(MOD(LEN2,2).NE.0) GOTO 902
        IF(MOD(LEN3,2).NE.0) GOTO 903
        IF(MOD(LEN4,2).NE.0) THEN

C          PAD SECTION 4 WITH AN ADDITIONAL BYTE
C          THAT IS ZEROED OUT.

           IAD4 = LEN0+LEN1+LEN2+LEN3
           IAD5 = IAD4+LEN4
           IBIT = IAD4*8
           LEN4 = LEN4+1
           CALL PKB(LEN4,24,MBAY,IBIT)
           IBIT = IAD5*8
           CALL PKB(0,8,MBAY,IBIT)
           MBYT = MBYT+1
        ENDIF
      ENDIF

C  WRITE SECTION 0 BYTE COUNT AND SECTION 5
C  ----------------------------------------

      IBIT = 0
      CALL PKC(BUFR, 4,MBAY,IBIT)
      CALL PKB(MBYT,24,MBAY,IBIT)

      KBIT = (MBYT-4)*8
      CALL PKC(SEVN, 4,MBAY,KBIT)

C  ZERO OUT THE EXTRA BYTES WHICH WILL BE WRITTEN
C  ----------------------------------------------

C     I.E. SINCE THE BUFR MESSAGE IS STORED WITHIN THE INTEGER ARRAY
C     MBAY(*) (RATHER THAN WITHIN A CHARACTER ARRAY), WE NEED TO MAKE
C     SURE THAT THE "7777" IS FOLLOWED BY ZEROED-OUT BYTES UP TO THE
C     BOUNDARY OF THE LAST MACHINE WORD THAT WILL BE WRITTEN OUT.

      CALL PADMSG(MBAY,MXMSGLD4,NPBYT)

C  WRITE THE MESSAGE PLUS PADDING TO A WORD BOUNDARY IF NULL(LUN) = 0
C  ------------------------------------------------------------------

      MWRD = NMWRD(MBAY)
      CALL STATUS(LUNIT,LUN,IL,IM)
      IF(NULL(LUN).EQ.0) then
         CALL BLOCKS(MBAY,MWRD)
         call cwrbufr(lun,mbay,mwrd)            
      ENDIF

      IF(IPRT.GE.2) THEN
      CALL ERRWRT('++++++++++++++BUFR ARCHIVE LIBRARY+++++++++++++++++')
      WRITE ( UNIT=ERRSTR, FMT='(A,I4,A,I7)')
     .  'BUFRLIB: MSGWRT: LUNIT =', LUNIT, ', BYTES =', MBYT+NPBYT
      CALL ERRWRT(ERRSTR)
      CALL ERRWRT('++++++++++++++BUFR ARCHIVE LIBRARY+++++++++++++++++')
      CALL ERRWRT(' ')
      ENDIF

C  SAVE A MEMORY COPY OF THIS MESSAGE, UNLESS IT'S A DX MESSAGE
C  ------------------------------------------------------------

      IF(IDXMSG(MBAY).NE.1) THEN

C        STORE A COPY OF THIS MESSAGE WITHIN COMMON /BUFRMG/,
C        FOR POSSIBLE LATER RETRIEVAL DURING THE NEXT CALL TO
C        SUBROUTINE WRITSA.

         MSGLEN = MWRD
         DO I=1,MSGLEN
           MSGTXT(I) = MBAY(I)
         ENDDO
      ENDIF

C  EXITS
C  -----

      RETURN
901   CALL BORT
     . ('BUFRLIB: MSGWRT - LENGTH OF SECTION 1 IS NOT A MULTIPLE OF 2')
902   CALL BORT
     . ('BUFRLIB: MSGWRT - LENGTH OF SECTION 2 IS NOT A MULTIPLE OF 2')
903   CALL BORT
     . ('BUFRLIB: MSGWRT - LENGTH OF SECTION 3 IS NOT A MULTIPLE OF 2')
      END
