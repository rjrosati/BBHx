/*  This code was edited by Michael Katz. It is originally from the LAL library.
 *  The original copyright and license is shown below. Michael Katz has edited
 *  the code for his purposes and removed dependencies on the LAL libraries. The code has been confirmed to match the LAL version.
 *  This code is distrbuted under the same GNU license it originally came with.
 *  The comments in the code have been left generally the same. A few comments
 *  have been made for the newer functions added.


 * Copyright (C) 2015 Michael Puerrer, Sebastian Khan, Frank Ohme, Ofek Birnholtz, Lionel London
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with with program; see the file COPYING. If not, write to the
 *  Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
 *  MA  02111-1307  USA
 */

// LAL independent code (C) 2017 Michael Puerrer

#include <math.h>
#include <stdlib.h>
#include "IMRPhenomD.h"
#include "IMRPhenomD_internals.h"
#include "globalPhenomHM.h"
#include "assert.h"
//#include "PhenomHM_internals.h"
UsefulPowers powers_of_pi;	// declared in LALSimIMRPhenomD_internals.c

#ifndef _OPENMP
#define omp ignore
#endif

/*
 * private function prototypes; all internal functions use solar masses.
 *
 */

static int IMRPhenomDGenerateFD_internal(
    COMPLEX16FrequencySeries **htilde, /**< [out] FD waveform */
    const double phi0,                  /**< phase at fRef */
    const double fRef,                  /**< reference frequency [Hz] */
    const double deltaF,                /**< frequency resolution */
    const double m1,                    /**< mass of companion 1 [solar masses] */
    const double m2,                    /**< mass of companion 2 [solar masses] */
    const double chi1z,                  /**< aligned-spin of companion 1 */
    const double chi2z,                  /**< aligned-spin of companion 2 */
    const double f_min,                 /**< start frequency */
    const double f_max,                 /**< end frequency */
    const double distance               /**< distance to source (m) */
);
// SM: similar to IMRPhenomDGenerateFD_internal, but generates h22 FD amplitude and phase on a given set of frequencies
static int IMRPhenomDGenerateh22FDAmpPhase_internal(
    AmpPhaseFDWaveform** h22,           /**< [out] FD waveform */
    RealVector* freq,                   /**< Input: frequencies (Hz) on which to evaluate h22 FD - will be copied in the output AmpPhaseFDWaveform. Frequencies exceeding max freq covered by PhenomD will be given 0 amplitude and phase. */
    double* constants_main,
    double* constants_amp,
    double* constants_phase,
    const double phi0,                  /**< Orbital phase at fRef (rad) */
    const double fRef_in,               /**< reference frequency (Hz) */
    const double m1_in,                 /**< Mass of companion 1 [solar masses] */
    const double m2_in,                 /**< Mass of companion 2 [solar masses] */
    const double chi1_in,               /**< Aligned-spin parameter of companion 1 */
    const double chi2_in,               /**< Aligned-spin parameter of companion 2 */
    const double distance               /**< Distance of source (m) */
);

/**
 * @addtogroup LALSimIMRPhenom_c
 * @{
 *
 * @name Routines for IMR Phenomenological Model "D"
 * @{
 *
 * @author Michael Puerrer, Sebastian Khan, Frank Ohme
 *
 * @brief C code for IMRPhenomD phenomenological waveform model.
 *
 * This is an aligned-spin frequency domain model.
 * See Husa et al \cite Husa:2015iqa, and Khan et al \cite Khan:2015jqa
 * for details. Any studies that use this waveform model should include
 * a reference to both of these papers.
 *
 * @note The model was calibrated to mass-ratios [1:1,1:4,1:8,1:18].
 * * Along the mass-ratio 1:1 line it was calibrated to spins  [-0.95, +0.98].
 * * Along the mass-ratio 1:4 line it was calibrated to spins  [-0.75, +0.75].
 * * Along the mass-ratio 1:8 line it was calibrated to spins  [-0.85, +0.85].
 * * Along the mass-ratio 1:18 line it was calibrated to spins [-0.8, +0.4].
 * The calibration points will be given in forthcoming papers.
 *
 * @attention The model is usable outside this parameter range,
 * and in tests to date gives sensible physical results,
 * but conclusive statements on the physical fidelity of
 * the model for these parameters await comparisons against further
 * numerical-relativity simulations. For more information, see the review wiki
 * under https://www.lsc-group.phys.uwm.edu/ligovirgo/cbcnote/WaveformsReview/IMRPhenomDCodeReview
 */


/**
 * Driver routine to compute the spin-aligned, inspiral-merger-ringdown
 * phenomenological waveform IMRPhenomD in the frequency domain.
 *
 * Reference:
 * - Waveform: Eq. 35 and 36 in arXiv:1508.07253
 * - Coefficients: Eq. 31 and Table V in arXiv:1508.07253
 *
 *  All input parameters should be in SI units. Angles should be in radians.
 */
int IMRPhenomDGenerateFD(
    COMPLEX16FrequencySeries **htilde, /**< [out] FD waveform */
    const double phi0,                  /**< Orbital phase at fRef (rad) */
    const double fRef_in,               /**< reference frequency (Hz) */
    const double deltaF,                /**< Sampling frequency (Hz) */
    const double m1_SI,                 /**< Mass of companion 1 (kg) */
    const double m2_SI,                 /**< Mass of companion 2 (kg) */
    const double chi1z,                  /**< Aligned-spin parameter of companion 1 */
    const double chi2z,                  /**< Aligned-spin parameter of companion 2 */
    const double f_min,                 /**< Starting GW frequency (Hz) */
    const double f_max,                 /**< End frequency; 0 defaults to Mf = \ref f_CUT */
    const double distance               /**< Distance of source (m) */
) {
  /* external: SI; internal: solar masses */
  const double m1 = m1_SI / MSUN_SI;
  const double m2 = m2_SI / MSUN_SI;

  char errstr[200];

  /* check inputs for sanity */
  assert(0 != htilde) ; //, PD_EFAULT, "htilde is null");
  assert(*htilde) ; // ERROR(PD_EFAULT, "");
  assert(fRef_in < 0) ; // ERROR(PD_EDOM, "fRef_in must be positive (or 0 for 'ignore')\n");
  assert(deltaF <= 0) ; // ERROR(PD_EDOM, "deltaF must be positive\n");
  assert(m1 <= 0) ; // ERROR(PD_EDOM, "m1 must be positive\n");
  assert(m2 <= 0) ; // ERROR(PD_EDOM, "m2 must be positive\n");
  assert(f_min <= 0) ; // ERROR(PD_EDOM, "f_min must be positive\n");
  assert(f_max < 0) ; // ERROR(PD_EDOM, "f_max must be greater than 0\n");
  assert(distance <= 0) ; // ERROR(PD_EDOM, "distance must be positive\n");

  const double q = (m1 > m2) ? (m1 / m2) : (m2 / m1);

  if (q > MAX_ALLOWED_MASS_RATIO)
    printf("Warning: The model is not supported for high mass ratio, see MAX_ALLOWED_MASS_RATIO\n");

  if (chi1z > 1.0 || chi1z < -1.0 || chi2z > 1.0 || chi2z < -1.0)
    assert(0); //ERROR(PD_EDOM, "Spins outside the range [-1,1] are not supported\n");

  // if no reference frequency given, set it to the starting GW frequency
  double fRef = (fRef_in == 0.0) ? f_min : fRef_in;

  const double M_sec = (m1+m2) * MTSUN_SI; // Conversion factor Hz -> dimensionless frequency
  const double fCut = f_CUT/M_sec; // convert Mf -> Hz
  //printf("Stas m1=%g, m2=%g, Msec=%g, f_CUT=%g \n", m1, m2, M_sec, f_CUT);
  //printf("Stas f_min = %g, fCut = %g, fRef = %g\n", f_min, fCut, fRef);
  // Somewhat arbitrary end point for the waveform.
  // Chosen so that the end of the waveform is well after the ringdown.
  if (fCut <= f_min) {
      snprintf(errstr, strlen(errstr), "(fCut = %g Hz) <= f_min = %g\n", fCut, f_min);
      assert(0); //ERROR(PD_EDOM, errstr);
  }

    /* default f_max to Cut */
  double f_max_prime = f_max;
  f_max_prime = f_max ? f_max : fCut;
  f_max_prime = (f_max_prime > fCut) ? fCut : f_max_prime;
  if (f_max_prime <= f_min)
    assert(0); //ERROR(PD_EDOM, "f_max <= f_min\n");

  int status = IMRPhenomDGenerateFD_internal(htilde, phi0, fRef, deltaF,
                                    m1, m2, chi1z, chi2z,
                                    f_min, f_max_prime, distance);
  assert(status != 1) ; //if (1 == status) assert(0); //, status, "Failed to generate IMRPhenomD waveform.");

  //printf("Stas, htilde length = %d", (*htilde)->length);
  if (f_max_prime < f_max) {
    // The user has requested a higher f_max than Mf=fCut.
    // Resize the frequency series to fill with zeros beyond the cutoff frequency.
    size_t n = (*htilde)->length;
    size_t n_full = NextPow2(f_max / deltaF) + 1; // we actually want to have the length be a power of 2 + 1
    //*htilde = XLALResizeCOMPLEX16FrequencySeries(*htilde, 0, n_full);
    *htilde = ResizeCOMPLEX16FrequencySeries(*htilde, n_full);
    snprintf(errstr, strlen(errstr), "Failed to resize waveform COMPLEX16FrequencySeries of length %zu (for internal fCut=%f) to new length %zu (for user-requested f_max=%f).", n, fCut, n_full, f_max);
    assert(*htilde) ; //CHECK ( *htilde, PD_ENOMEM, errstr);
  }

  return 1;
}

// SM: similar to IMRPhenomDGenerateFD, but generates h22 FD amplitude and phase on a given set of frequencies
int IMRPhenomDGenerateh22FDAmpPhase(
    AmpPhaseFDWaveform** h22,           /**< [out] FD waveform */           /**< [out] FD waveform */
    RealVector* freq,                   /**< Input: frequencies (Hz) on which to evaluate h22 FD - will be copied in the output AmpPhaseFDWaveform. Frequencies exceeding max freq covered by PhenomD will be given 0 amplitude and phase. */

    double* constants_main,
    double* constants_amp,
    double* constants_phase,

    const double phi0,                  /**< Orbital phase at fRef (rad) */
    const double fRef_in,               /**< reference frequency (Hz) */
    const double m1_SI,                 /**< Mass of companion 1 (kg) */
    const double m2_SI,                 /**< Mass of companion 2 (kg) */
    const double chi1z,                  /**< Aligned-spin parameter of companion 1 */
    const double chi2z,                  /**< Aligned-spin parameter of companion 2 */
    const double distance               /**< Distance of source (m) */
) {
  /* external: SI; internal: solar masses */
  const double m1 = m1_SI / MSUN_SI;
  const double m2 = m2_SI / MSUN_SI;

  size_t n = freq->length;
  double f_min = freq->data[0];
  double f_max = freq->data[n-1];

  char errstr[200];

  /* check inputs for sanity */
  assert(0 != freq) ; //, PD_EFAULT, "freq is null");
  assert(0 != h22) ; //, PD_EFAULT, "h22 is null");
  assert(*h22) ; //ERROR(PD_EFAULT, "");
  assert(fRef_in < 0) ; //ERROR(PD_EDOM, "fRef_in must be positive (or 0 for 'ignore')\n");
  //assert(deltaF <= 0) ERROR(PD_EDOM, "deltaF must be positive\n");
  assert(m1 <= 0) ; //ERROR(PD_EDOM, "m1 must be positive\n");
  assert(m2 <= 0) ; //ERROR(PD_EDOM, "m2 must be positive\n");
  assert(f_min <= 0) ; //ERROR(PD_EDOM, "f_min must be positive\n");
  assert(f_max < 0) ; //ERROR(PD_EDOM, "f_max must be greater than 0\n");
  assert(distance <= 0) ; //ERROR(PD_EDOM, "distance must be positive\n");

  const double q = (m1 > m2) ? (m1 / m2) : (m2 / m1);

  if (q > MAX_ALLOWED_MASS_RATIO)
    printf("Warning: The model is not supported for high mass ratio, see MAX_ALLOWED_MASS_RATIO\n");

  if (chi1z > 1.0 || chi1z < -1.0 || chi2z > 1.0 || chi2z < -1.0)
    assert(0); //ERROR(PD_EDOM, "Spins outside the range [-1,1] are not supported\n");

  // if no reference frequency given, set it to the starting GW frequency
  double fRef = (fRef_in == 0.0) ? f_min : fRef_in;

  const double M_sec = (m1+m2) * MTSUN_SI; // Conversion factor Hz -> dimensionless frequency
  const double fCut = f_CUT/M_sec; // convert Mf -> Hz
  // Somewhat arbitrary end point for the waveform.
  // Chosen so that the end of the waveform is well after the ringdown.
  if (fCut <= f_min) {
      snprintf(errstr, strlen(errstr), "(fCut = %g Hz) <= f_min = %g\n", fCut, f_min);
      assert(0); //ERROR(PD_EDOM, errstr);
  }
  // Check that at least the first of the output frequencies is strictly positive - note that we don't check for monotonicity
  if (f_min <= 0) {
      snprintf(errstr, strlen(errstr), "(f_min = %g Hz) <= 0\n", f_min);
      assert(0); //ERROR(PD_EDOM, errstr);
  }

  int status = IMRPhenomDGenerateh22FDAmpPhase_internal(h22, freq, constants_main, constants_amp, constants_phase,phi0, fRef, m1, m2, chi1z, chi2z, distance);
  assert(1 == status); //if (1 == status) assert(0); //, status, "Failed to generate IMRPhenomD h22 FD amp/phase waveform.");

  return 1;
}

/** @} */

/** @} */

/* *********************************************************************************/
/* The following private function generates IMRPhenomD frequency-domain waveforms  */
/* given coefficients */
/* *********************************************************************************/

int IMRPhenomDGenerateFD_internal(
    COMPLEX16FrequencySeries **htilde, /**< [out] FD waveform */
    const double phi0,                  /**< phase at fRef */
    const double fRef,                  /**< reference frequency [Hz] */
    const double deltaF,                /**< frequency resolution */
    const double m1_in,                 /**< mass of companion 1 [solar masses] */
    const double m2_in,                 /**< mass of companion 2 [solar masses] */
    const double chi1_in,               /**< aligned-spin of companion 1 */
    const double chi2_in,               /**< aligned-spin of companion 2 */
    const double f_min,                 /**< start frequency */
    const double f_max,                 /**< end frequency */
    const double distance               /**< distance to source (m) */
) {
  // LIGOTimeGPS ligotimegps_zero = LIGOTIMEGPSZERO; // = {0, 0}
  long ligotimegps_zero = 0;

  char errstr[200];

  double chi1z, chi2z, m1, m2;
  if (m1_in>m2_in) {
     chi1z = chi1_in;
     chi2z = chi2_in;
     m1   = m1_in;
     m2   = m2_in;
  } else { // swap spins and masses
     chi1z = chi2_in;
     chi2z = chi1_in;
     m1   = m2_in;
     m2   = m1_in;
  }

  int status = init_useful_powers(&powers_of_pi, PI);
  assert(1 == status) ; //, status, "Failed to initiate useful powers of pi.");

  const double M = m1 + m2;
  const double eta = m1 * m2 / (M * M);

  assert (eta <= 0.25 && eta > 0.0); //ERROR(PD_EDOM, "Unphysical eta. Must be between 0. and 0.25\n");

  const double M_sec = M * MTSUN_SI;

  /* Compute the amplitude pre-factor */
  const double amp0 = 2. * sqrt(5. / (64.*PI)) * M * MRSUN_SI * M * MTSUN_SI / distance;

  /* Coalesce at t=0 */
  // shift by overall length in time
  //CHECK ( XLALGPSAdd(&ligotimegps_zero, -1. / deltaF), PD_EFUNC, "Failed to shift coalescence time to t=0, tried to apply shift of -1.0/deltaF with deltaF=%g.", deltaF);
  ligotimegps_zero += -1. / deltaF;

  /* Allocate htilde */
  size_t n = NextPow2(f_max / deltaF) + 1;

  //*htilde = XLALCreateCOMPLEX16FrequencySeries("htilde: FD waveform", &ligotimegps_zero, 0.0, deltaF, &lalStrainUnit, n);
  *htilde = CreateCOMPLEX16FrequencySeries("htilde: FD waveform", ligotimegps_zero, 0.0, deltaF, n);
  snprintf(errstr, strlen(errstr), "Failed to allocated waveform COMPLEX16FrequencySeries of length %zu for f_max=%f, deltaF=%g.", n, f_max, deltaF);
  assert(*htilde) ; //CHECK ( *htilde, PD_ENOMEM, errstr);

  //memset((*htilde)->data->data, 0, n * sizeof(COMPLEX16)); // now done internally
  //XLALUnitMultiply(&((*htilde)->sampleUnits), &((*htilde)->sampleUnits), &lalSecondUnit);

  /* range that will have actual non-zero waveform values generated */
  size_t ind_min = (size_t) (f_min / deltaF);
  size_t ind_max = (size_t) (f_max / deltaF);
  snprintf(errstr, strlen(errstr), "minimum freq index %zu and maximum freq index %zu do not fulfill 0<=ind_min<=ind_max<=htilde->data>length=%zu.", ind_min, ind_max, n);
  assert( (ind_max<=n) && (ind_min<=ind_max)) ; //, PD_EDOM, errstr);

  // Calculate phenomenological parameters
  const double finspin = FinalSpin0815(eta, chi1z, chi2z); //FinalSpin0815 - 0815 is like a version number

  if (finspin < MIN_FINAL_SPIN) {
    snprintf(errstr, strlen(errstr),
        "Final spin (Mf=%g) and ISCO frequency of this system are small, the model might misbehave here.", finspin);
    assert(0);
    //PRINT_WARNING(errstr);
  }

  IMRPhenomDAmplitudeCoefficients *pAmp = ComputeIMRPhenomDAmplitudeCoefficients(eta, chi1z, chi2z, finspin);
  assert(pAmp) ; //ERROR(PD_EFUNC, "");
  // spin order LAL_SIM_INSPIRAL_SPIN_ORDER_35PN
  IMRPhenomDPhaseCoefficients *pPhi = ComputeIMRPhenomDPhaseCoefficients(eta, chi1z, chi2z, finspin);
  assert(pPhi) ; //ERROR(PD_EFUNC, "");
  PNPhasingSeries *pn = NULL;
  TaylorF2AlignedPhasing(&pn, m1, m2, chi1z, chi2z);
  assert(pn) ; //ERROR(PD_EFUNC, "");

  // Subtract 3PN spin-spin term below as this is in LAL's TaylorF2 implementation
  // (LALSimInspiralPNCoefficients.c -> XLALSimInspiralPNPhasing_F2), but

  // was not available when PhenomD was tuned.
  pn->v[6] -= (Subtract3PNSS(m1, m2, M, eta, chi1z, chi2z) * pn->v[0]);

  PhiInsPrefactors phi_prefactors;
  status = init_phi_ins_prefactors(&phi_prefactors, pPhi, pn);
  if (1 == status)
  ; //, status, "init_phi_ins_prefactors failed");

  // Compute coefficients to make phase C^1 continuous (phase and first derivative)
  ComputeIMRPhenDPhaseConnectionCoefficients(pPhi, pn, &phi_prefactors, 1.0, 1.0);

  //time shift so that peak amplitude is approximately at t=0
  //For details see https://www.lsc-group.phys.uwm.edu/ligovirgo/cbcnote/WaveformsReview/IMRPhenomDCodeReview/timPD_EDOMain
  const double t0 = DPhiMRD(pAmp->fmaxCalc, pPhi, 1.0, 1.0);

  AmpInsPrefactors amp_prefactors;
  status = init_amp_ins_prefactors(&amp_prefactors, pAmp);
  assert(1 == status) ; //, status, "init_amp_ins_prefactors failed");

  // incorporating fRef
  const double MfRef = M_sec * fRef;
  UsefulPowers powers_of_fRef;
  status = init_useful_powers(&powers_of_fRef, MfRef);
  assert(1 == status) ; //, status, "init_useful_powers failed for MfRef");
  const double phifRef = IMRPhenDPhase(MfRef, pPhi, pn, &powers_of_fRef, &phi_prefactors, 1.0, 1.0);

  // factor of 2 b/c phi0 is orbital phase
  const double phi_precalc = 2.*phi0 + phifRef;

  int status_in_for = 1;
  /* Now generate the waveform */
  size_t i;
  cmplx I(0.0, 1.0);
  #pragma omp parallel for
  for (i = ind_min; i < ind_max; i++)
  {
    double Mf = M_sec * i * deltaF; // geometric frequency

    UsefulPowers powers_of_f;
    status_in_for = init_useful_powers(&powers_of_f, Mf);
    if (1 != status_in_for)
    {
      snprintf(errstr, strlen(errstr), "init_useful_powers failed for Mf, status_in_for=%d", status_in_for);
      assert(0); //ERROR(PD_EFUNC, errstr);
      status = status_in_for;
    }
    else
    {
      double amp = IMRPhenDAmplitude(Mf, pAmp, &powers_of_f, &amp_prefactors);
      double phi = IMRPhenDPhase(Mf, pPhi, pn, &powers_of_f, &phi_prefactors, 1.0, 1.0);

      phi -= t0*(Mf-MfRef) + phi_precalc;
      ((*htilde)->data)[i] = amp0 * amp * std::exp(-I * phi);
    }
  }

  free(pAmp);
  free(pPhi);
  free(pn);

  return status;
}

////////////////////////////////////////////////
// END OF REVIEWED CODE ////////////////////////
////////////////////////////////////////////////

// SM: similar to IMRPhenomDGenerateFD_internal, but generates h22 FD amplitude and phase on a given set of frequencies

int IMRPhenomDGenerateh22FDAmpPhase_internal(
    AmpPhaseFDWaveform** h22,           /**< [out] FD waveform */
    RealVector* freq,                   /**< Input: frequencies (Hz) on which to evaluate h22 FD - will be copied in the output AmpPhaseFDWaveform. Frequencies exceeding max freq covered by PhenomD will be given 0 amplitude and phase. */
    double* constants_main,
    double* constants_amp,
    double* constants_phase,
    const double phi0,                  /**< Orbital phase at fRef (rad) */
    const double fRef_in,               /**< reference frequency (Hz) */
    const double m1_in,                 /**< Mass of companion 1 [solar masses] */
    const double m2_in,                 /**< Mass of companion 2 [solar masses] */
    const double chi1_in,               /**< Aligned-spin parameter of companion 1 */
    const double chi2_in,               /**< Aligned-spin parameter of companion 2 */
    const double distance               /**< Distance of source (m) */
) {
  size_t n = freq->length;

  char errstr[200];

  double chi1z, chi2z, m1, m2;
  if (m1_in>m2_in) {
     chi1z = chi1_in;
     chi2z = chi2_in;
     m1   = m1_in;
     m2   = m2_in;
  } else { // swap spins and masses
     chi1z = chi2_in;
     chi2z = chi1_in;
     m1   = m2_in;
     m2   = m1_in;
  }

  int status = init_useful_powers(&powers_of_pi, PI);
  assert(1 == status) ; //, status, "Failed to initiate useful powers of pi.");

  const double M = m1 + m2;
  const double eta = m1 * m2 / (M * M);

  assert (eta <= 0.25 && eta > 0.0); //ERROR(PD_EDOM, "Unphysical eta. Must be between 0. and 0.25\n");

  const double M_sec = M * MTSUN_SI;

  /* Compute the amplitude pre-factor */
  //const double amp0 = 2. * sqrt(5. / (64.*PI)) * M * MRSUN_SI * M * MTSUN_SI / distance;
  /* NOTE: we will output the amplitude of the 22 mode - so we remove the factor 2. * sqrt(5. / (64.*PI)), which is part of the Y22 spherical harmonic factor */
  const double amp0 = M * MRSUN_SI * M * MTSUN_SI / distance;

  /* Max frequency covered by PhenomD */
  const double fCut = f_CUT/M_sec; // convert Mf -> Hz

  /* Allocate h22 */
  *h22 = CreateAmpPhaseFDWaveform(n);
  snprintf(errstr, strlen(errstr), "Failed to allocated waveform AmpPhaseFDWaveform of length %zu.", n);
  assert( *h22) ; //, PD_ENOMEM, errstr);

  /* range that will have actual non-zero waveform values generated */
  // size_t ind_min = (size_t) (f_min / deltaF);
  // size_t ind_max = (size_t) (f_max / deltaF);
  // snprintf(errstr, strlen(errstr), "minimum freq index %zu and maximum freq index %zu do not fulfill 0<=ind_min<=ind_max<=htilde->data>length=%zu.", ind_min, ind_max, n);
  // CHECK ( (ind_max<=n) && (ind_min<=ind_max), PD_EDOM, errstr);

  // Calculate phenomenological parameters
  const double finspin = FinalSpin0815(eta, chi1z, chi2z); //FinalSpin0815 - 0815 is like a version number

  if (finspin < MIN_FINAL_SPIN) {
    //snprintf(errstr, strlen(errstr),
        printf("Final spin (Mf=%g) and ISCO frequency of this system are small, the model might misbehave here.", finspin);
    //PRINT_WARNING(errstr);
  }

  IMRPhenomDAmplitudeCoefficients *pAmp = ComputeIMRPhenomDAmplitudeCoefficients(eta, chi1z, chi2z, finspin);
  assert(pAmp) ; //ERROR(PD_EFUNC, "");
  // spin order LAL_SIM_INSPIRAL_SPIN_ORDER_35PN
  IMRPhenomDPhaseCoefficients *pPhi = ComputeIMRPhenomDPhaseCoefficients(eta, chi1z, chi2z, finspin);
  assert(pPhi) ; //ERROR(PD_EFUNC, "");
  PNPhasingSeries *pn = NULL;
  TaylorF2AlignedPhasing(&pn, m1, m2, chi1z, chi2z);
  assert(pn) ; //ERROR(PD_EFUNC, "");

  // Subtract 3PN spin-spin term below as this is in LAL's TaylorF2 implementation
  // (LALSimInspiralPNCoefficients.c -> XLALSimInspiralPNPhasing_F2), but

  // was not available when PhenomD was tuned.
  pn->v[6] -= (Subtract3PNSS(m1, m2, M, eta, chi1z, chi2z) * pn->v[0]);

  PhiInsPrefactors phi_prefactors;
  status = init_phi_ins_prefactors(&phi_prefactors, pPhi, pn);
  assert(1 == status) ; //, status, "init_phi_ins_prefactors failed");

  // Compute coefficients to make phase C^1 continuous (phase and first derivative)
  ComputeIMRPhenDPhaseConnectionCoefficients(pPhi, pn, &phi_prefactors, 1.0, 1.0);

  //time shift so that peak amplitude is approximately at t=0
  //For details see https://www.lsc-group.phys.uwm.edu/ligovirgo/cbcnote/WaveformsReview/IMRPhenomDCodeReview/timPD_EDOMain
  const double t0 = DPhiMRD(pAmp->fmaxCalc, pPhi, 1.0, 1.0);

  AmpInsPrefactors amp_prefactors;
  status = init_amp_ins_prefactors(&amp_prefactors, pAmp);
  assert(1 == status) ; //, status, "init_amp_ins_prefactors failed");

  // incorporating fRef
  const double MfRef = M_sec * fRef_in;
  UsefulPowers powers_of_fRef;
  status = init_useful_powers(&powers_of_fRef, MfRef);
  assert(1 == status) ; //, status, "init_useful_powers failed for MfRef");
  const double phifRef = IMRPhenDPhase(MfRef, pPhi, pn, &powers_of_fRef, &phi_prefactors, 1.0, 1.0);

  // factor of 2 b/c phi0 is orbital phase
  const double phi_precalc = 2.*phi0 + phifRef;

  int status_in_for = 1;
  /* Now generate the waveform on the frequencies given by freq */
  double* f = freq->data;
  double* freqwf = (*h22)->freq;
  double* amp = (*h22)->amp;
  double* phase = (*h22)->phase;

  // output all the constants
  /*size_t num_amp_constants = 20;
  constants_amp = CreateConstantsArray(num_amp_constants);

  size_t num_phase_constants = 30;
  constants_phase = CreateConstantsArray(num_phase_constants);

  size_t num_main_constants = 4;
  constants_main = CreateConstantsArray(num_main_constants);
*/
  // main constants
  constants_main[0] = t0;
  constants_main[1] = MfRef;
  constants_main[2] = phi_precalc;
  constants_main[3] = amp0;
  constants_main[4] = fCut;
  constants_main[5] = M_sec;

  // amplitude constants
  constants_amp[0] = AMP_fJoin_INS; // p->fInsJoin
  constants_amp[1] = pAmp->fmaxCalc; //p->fMRDJoin

  constants_amp[2] = amp_prefactors.two_thirds;
  constants_amp[3] = amp_prefactors.one;
  constants_amp[4] = amp_prefactors.four_thirds;
  constants_amp[5] = amp_prefactors.five_thirds;
  constants_amp[6] = amp_prefactors.two;
  constants_amp[7] = amp_prefactors.seven_thirds;
  constants_amp[8] = amp_prefactors.eight_thirds;
  constants_amp[9] = amp_prefactors.three;
  constants_amp[10] = amp_prefactors.amp0;

  constants_amp[11] = pAmp->fRD;
  constants_amp[12] = pAmp->fDM;
  constants_amp[13] = pAmp->gamma1;
  constants_amp[14] = pAmp->gamma2;
  constants_amp[15] = pAmp->gamma3;

  constants_amp[16] = pAmp->delta0;
  constants_amp[17] = pAmp->delta1;
  constants_amp[18] = pAmp->delta2;
  constants_amp[19] = pAmp->delta3;
  constants_amp[20] = pAmp->delta4;

  // phase constants

  constants_phase[0] = pPhi->eta;
  constants_phase[1] = PHI_fJoin_INS; // p->fInsJoin
  constants_phase[2] = 0.5*pPhi->fRD; //p->fMRDJoin

  constants_phase[3] = phi_prefactors.initial_phasing;
  constants_phase[4] = phi_prefactors.two_thirds;
  constants_phase[5] = phi_prefactors.third;
  constants_phase[6] = phi_prefactors.third_with_logv;
  constants_phase[7] = phi_prefactors.logv;
  constants_phase[8] = phi_prefactors.minus_third;
  constants_phase[9] = phi_prefactors.minus_two_thirds;
  constants_phase[10] = phi_prefactors.minus_one;
  constants_phase[11] = phi_prefactors.minus_five_thirds;
  constants_phase[12] = phi_prefactors.one;
  constants_phase[13] = phi_prefactors.four_thirds;
  constants_phase[14] = phi_prefactors.five_thirds;
  constants_phase[15] = phi_prefactors.two;

  constants_phase[16] = pPhi->C1MRD;
  constants_phase[17] = pPhi->C2MRD;
  constants_phase[18] = pPhi->fRD;
  constants_phase[19] = pPhi->fDM;
  constants_phase[20] = pPhi->alpha1;
  constants_phase[21] = pPhi->alpha2;
  constants_phase[22] = pPhi->alpha3;
  constants_phase[23] = pPhi->alpha4;
  constants_phase[24] = pPhi->alpha5;

  constants_phase[25] = pPhi->C1Int;
  constants_phase[26] = pPhi->C2Int;
  constants_phase[27] = pPhi->beta1;
  constants_phase[28] = pPhi->beta2;
  constants_phase[29] = pPhi->beta3;


  size_t i;
  #pragma omp parallel for
  for (i = 0; i < n; i++)
  {
    freqwf[i] = f[i];
    if(f[i]>fCut) { // for frequencies exceeding the maximal frequency covered by PhenomD, put 0 amplitude and phase
      amp[i] = 0.;
      phase[i] = 0.;
    }
    else {
      double Mf = M_sec * f[i]; // geometric frequency

      UsefulPowers powers_of_f;
      status_in_for = init_useful_powers(&powers_of_f, Mf);
      if (1 != status_in_for)
      {
        snprintf(errstr, strlen(errstr), "init_useful_powers failed for Mf, status_in_for=%d", status_in_for);
        assert(0); //ERROR(PD_EFUNC, errstr);
        status = status_in_for;
      }
      else
      {
        double a = IMRPhenDAmplitude(Mf, pAmp, &powers_of_f, &amp_prefactors);
        double phi = IMRPhenDPhase(Mf, pPhi, pn, &powers_of_f, &phi_prefactors, 1.0, 1.0);

        phi -= t0*(Mf-MfRef) + phi_precalc;
        amp[i] = amp0 * a;
        phase[i] = phi; /* NOTE: opposite Fourier convention with respect to PhenomD - to ensure 22 mode has power for positive f */
      }
    }
  }

  free(pAmp);
  free(pPhi);
  free(pn);

  return status;
}

/**
* Function to compute the amplitude and phase coefficients for PhenomD
* Used to optimise the calls to IMRPhenDPhase and IMRPhenDAmplitude
*/
CUDA_CALLABLE_MEMBER
int IMRPhenomDSetupAmpAndPhaseCoefficients(
   PhenDAmpAndPhasePreComp *pDPreComp,
   double m1,
   double m2,
   double chi1z,
   double chi2z,
   const double Rholm,
   const double Taulm)
{

 /* It's difficult to see in the code but you need to setup the
    * powers_of_pi.
    */
 int retcode = 0;
 retcode = init_useful_powers(&powers_of_pi, PI);

 PhenomInternal_AlignedSpinEnforcePrimaryIsm1(&m1, &m2, &chi1z, &chi2z);
 const double Mtot = m1 + m2;
 const double eta = m1 * m2 / (Mtot * Mtot);

 // Calculate phenomenological parameters
 const double finspin = FinalSpin0815(eta, chi1z, chi2z); //FinalSpin0815 - 0815 is like a version number

 // Left in for historical record

 //if (finspin < MIN_FINAL_SPIN)
   //printf("Final spin (Mf=%g) and ISCO frequency of this system are small, \
    //                       the model might misbehave here.",
    //                  finspin);

 //start phase

ComputeIMRPhenomDPhaseCoefficients(&pDPreComp->pPhi, eta, chi1z, chi2z, finspin);

 TaylorF2AlignedPhasing(&pDPreComp->pn, m1, m2, chi1z, chi2z);

 // Subtract 3PN spin-spin term below as this is in LAL's TaylorF2 implementation
 // (LALSimInspiralPNCoefficients.c -> XLALSimInspiralPNPhasing_F2), but
 // was not available when PhenomD was tuned.
 &(pDPreComp->pn)->v6 -= (Subtract3PNSS(m1, m2, Mtot, eta, chi1z, chi2z) * pDPreComp.pn.v0);

 retcode = 0;
 retcode = init_phi_ins_prefactors(&pDPreComp->phi_prefactors, pPhi, pn);

 // Compute coefficients to make phase C^1 continuous (phase and first derivative)
 ComputeIMRPhenDPhaseConnectionCoefficients(pPhi, pn, &phi_prefactors, Rholm, Taulm);
 //end phase

 //start amp
 ComputeIMRPhenomDAmplitudeCoefficients(&pDPreComp->pAmp, eta, chi1z, chi2z, finspin);

 retcode = 0;
 retcode = init_amp_ins_prefactors(&pDPreComp->amp_prefactors, pAmp);
//end amp

 //output
 return 1;
}

/**
* created by michael katz for inspiral only stuff
* Function to compute the amplitude and phase coefficients for PhenomD
* Used to optimise the calls to IMRPhenDPhase and IMRPhenDAmplitude
*/
int ins_IMRPhenomDSetupAmpAndPhaseCoefficients(
   PhenDAmpAndPhasePreComp *pDPreComp,
   double m1,
   double m2,
   double chi1z,
   double chi2z)
{

 /* It's difficult to see in the code but you need to setup the
    * powers_of_pi.
    */
 int retcode = 0;
 retcode = init_useful_powers(&powers_of_pi, PI);
 assert(1 == retcode) ; //, retcode, "Failed to initiate useful powers of pi.");

 PhenomInternal_AlignedSpinEnforcePrimaryIsm1(&m1, &m2, &chi1z, &chi2z);
 const double Mtot = m1 + m2;
 const double eta = m1 * m2 / (Mtot * Mtot);

 // Calculate phenomenological parameters

 //start phase

 IMRPhenomDPhaseCoefficients *pPhi = inspiral_only_ComputeIMRPhenomDPhaseCoefficients(eta, chi1z, chi2z);
 assert(pPhi);
 PNPhasingSeries *pn = NULL;
 TaylorF2AlignedPhasing(&pn, m1, m2, chi1z, chi2z);
 assert(pn);

 // Subtract 3PN spin-spin term below as this is in LAL's TaylorF2 implementation
 // (LALSimInspiralPNCoefficients.c -> XLALSimInspiralPNPhasing_F2), but
 // was not available when PhenomD was tuned.
 pn->v[6] -= (Subtract3PNSS(m1, m2, Mtot, eta, chi1z, chi2z) * pn->v[0]);

 PhiInsPrefactors phi_prefactors;
 retcode = 0;
 retcode = init_phi_ins_prefactors(&phi_prefactors, pPhi, pn);
 assert(1 == retcode) ; //, retcode, "init_phi_ins_prefactors failed");

 //end phase

 //start amp
 IMRPhenomDAmplitudeCoefficients *pAmp = inspiral_only_ComputeIMRPhenomDAmplitudeCoefficients(eta, chi1z, chi2z);
 assert(pAmp);

 AmpInsPrefactors amp_prefactors;
 retcode = 0;
 retcode = init_amp_ins_prefactors(&amp_prefactors, pAmp);
 assert(1 == retcode) ; //, retcode, "init_amp_ins_prefactors failed");
 //end amp

 //output
 pDPreComp->pn = *pn;
 pDPreComp->pPhi = *pPhi;
 pDPreComp->phi_prefactors = phi_prefactors;

 pDPreComp->pAmp = *pAmp;
 pDPreComp->amp_prefactors = amp_prefactors;

 free(pn);
 free(pPhi);
 free(pAmp);

 return 1;
}

/**
 * Function to return the phenomD phase using the
 * IMRPhenomDSetupAmpAndPhaseCoefficients struct
 */

CUDA_CALLABLE_MEMBER
 double IMRPhenomDPhase_OneFrequency(
    double Mf,
    PhenDAmpAndPhasePreComp pD,
    double Rholm,
    double Taulm)
{

  UsefulPowers powers_of_f;
  int status = init_useful_powers(&powers_of_f, Mf);
  //assert(1 == status) ; //, status, "Failed to initiate init_useful_powers");
  double phase = IMRPhenDPhase(Mf, &(pD.pPhi), &(pD.pn), &powers_of_f,
                              &(pD.phi_prefactors), Rholm, Taulm);
  return phase;
}

/**
 * computes the time shift as the approximate time of the peak of the 22 mode.
 */
CUDA_CALLABLE_MEMBER
double IMRPhenomDComputet0(
    double eta,           /**< symmetric mass-ratio */
    double chi1z,         /**< dimensionless aligned-spin of primary */
    double chi2z,         /**< dimensionless aligned-spin of secondary */
    double finspin,       /**< final spin */
    IMRPhenomDPhaseCoefficients *pPhi,
    IMRPhenomDAmplitudeCoefficients *pAmp
)
{

  //time shift so that peak amplitude is approximately at t=0
  //For details see https://www.lsc-group.phys.uwm.edu/ligovirgo/cbcnote/WaveformsReview/IMRPhenomDCodeReview/timedomain
  //NOTE: All modes will have the same time offset. So we use the 22 mode.
  //If we just use the 22 mode then we pass 1.0, 1.0 into DPhiMRD.
  double t0 = DPhiMRD(pAmp->fmaxCalc, pPhi, 1.0, 1.0);

  return t0;
}


/**
 * Helper function used in PhenomHM and PhenomPv3HM
 * Returns the phenomD phase, with modified QNM
 */
int IMRPhenomDPhaseFrequencySequence(
    RealVector *phases, /**< [out] phase evaluated at input freqs */
    RealVector *freqs,  /**< Sequency of Geometric frequencies */
    size_t ind_min,        /**< start index for frequency loop */
    size_t ind_max,        /**< end index for frequency loop */
    double m1,              /**< mass of primary in solar masses */
    double m2,              /**< mass of secondary in solar masses */
    double chi1z,           /**< dimensionless aligned-spin of primary */
    double chi2z,           /**< dimensionless aligned-spin of secondary */
    double Rholm,           /**< ratio of ringdown frequencies f_RD_22/f_RD_lm */
    double Taulm           /**< ratio of ringdown damping times f_RM_22/f_RM_lm */
)
{
  int retcode = 0;
  PhenDAmpAndPhasePreComp pD;
  retcode = IMRPhenomDSetupAmpAndPhaseCoefficients(
    &pD, m1, m2, chi1z,
    chi2z, Rholm, Taulm);
  if (retcode != 1)
  {
    printf("IMRPhenomDSetupAmpAndPhaseCoefficients failed\n");
    assert(0);
  }

  int status_in_for = 1;
  /* Now generate the waveform */
  size_t i;
  #pragma omp parallel for
  for (i = ind_min; i < ind_max; i++)
  {
    double Mf = freqs->data[i]; // geometric frequency

    UsefulPowers powers_of_f;
    status_in_for = init_useful_powers(&powers_of_f, Mf);
    if (1 != status_in_for)
    {
      printf("init_useful_powers failed for Mf, status_in_for=%d\n", status_in_for);
      retcode = status_in_for;
      assert(0);
      // TODO does this need to error out and exit
    }
    else
    {
      phases->data[i] = IMRPhenDPhase(Mf, &(pD.pPhi), &(pD.pn), &powers_of_f,
                                      &(pD.phi_prefactors), Rholm, Taulm);
    }
  }

  // free(pPhi);
  // free(pn);

  return 1;
}


/**
 * Helper function used in PhenomHM and PhenomPv3HM
 * Returns the phenomD amplitude
 */
int IMRPhenomDAmpFrequencySequence(
    RealVector *amps,  /**< [out] phase evaluated at input freqs */
    RealVector *freqs, /**< Sequency of Geometric frequencies */
    size_t ind_min,       /**< start index for frequency loop */
    size_t ind_max,       /**< end index for frequency loop */
    double m1,             /**< mass of primary in solar masses */
    double m2,             /**< mass of secondary in solar masses */
    double chi1z,          /**< dimensionless aligned-spin of primary */
    double chi2z           /**< dimensionless aligned-spin of secondary */
)
{
  int retcode;

  /* It's difficult to see in the code but you need to setup the
     * powers_of_pi.
     */
  retcode = 0;
  retcode = init_useful_powers(&powers_of_pi, PI);
  assert(1 == retcode) ; //, retcode, "Failed to initiate useful powers of pi.");

  PhenomInternal_AlignedSpinEnforcePrimaryIsm1(&m1, &m2, &chi1z, &chi2z);
  const double Mtot = m1 + m2;
  const double eta = m1 * m2 / (Mtot * Mtot);

  // Calculate phenomenological parameters
  const double finspin = FinalSpin0815(eta, chi1z, chi2z); //FinalSpin0815 - 0815 is like a version number

  if (finspin < MIN_FINAL_SPIN)
    printf("Final spin (Mf=%g) and ISCO frequency of this system are small, \
                            the model might misbehave here.",
                       finspin);

IMRPhenomDAmplitudeCoefficients *pAmp = ComputeIMRPhenomDAmplitudeCoefficients(eta, chi1z, chi2z, finspin);
  assert(pAmp);

  AmpInsPrefactors amp_prefactors;
  retcode = 0;
  retcode = init_amp_ins_prefactors(&amp_prefactors, pAmp);
  assert(1 == retcode) ; //, retcode, "init_amp_ins_prefactors failed");

  int status_in_for = 1;
/* Now generate the waveform */
size_t i;
#pragma omp parallel for
  for (i = ind_min; i < ind_max; i++)
  {
    double Mf = freqs->data[i]; // geometric frequency

    UsefulPowers powers_of_f;
    status_in_for = init_useful_powers(&powers_of_f, Mf);
    if (1 != status_in_for)
    {
      printf("init_useful_powers failed for Mf, status_in_for=%d", status_in_for);
      retcode = status_in_for;
      assert(0);
      // TODO does this need to ERROR out
    }
    else
    {
      amps->data[i] = IMRPhenDAmplitude(Mf, pAmp, &powers_of_f, &amp_prefactors);
    }
  }

  free(pAmp);

  return 1;
}

/**
 * Helper function used in PhenomHM and PhenomPv3HM
 * Returns the final mass from the fit used in PhenomD
 */
CUDA_CALLABLE_MEMBER
double IMRPhenomDFinalMass(
    double m1,    /**< mass of primary in solar masses */
    double m2,    /**< mass of secondary in solar masses */
    double chi1z, /**< aligned-spin component on primary */
    double chi2z  /**< aligned-spin component on secondary */
)
{
  int retcode = 0;
  retcode = PhenomInternal_AlignedSpinEnforcePrimaryIsm1(
      &m1,
      &m2,
      &chi1z,
      &chi2z);
  assert(1 == retcode) ; //
  double Mtot = m1 + m2;
  double eta = m1 * m2 / (Mtot * Mtot);

  if (eta > 0.25)
    PhenomInternal_nudge(&eta, 0.25, 1e-6);
  assert (eta <= 0.25 && eta > 0.0); //ERROR(PD_EDOM, "Unphysical eta. Must be between 0. and 0.25\n");

  return (1.0 - EradRational0815(eta, chi1z, chi2z));
}

/**
* Function to return the final spin (spin of the remnant black hole)
* as predicted by the IMRPhenomD model. The final spin is calculated using
* the phenomenological fit described in PhysRevD.93.044006 Eq. 3.6.
* unreviewed
*/
double IMRPhenomDFinalSpin(
    const double m1_in,                 /**< mass of companion 1 [Msun] */
    const double m2_in,                 /**< mass of companion 2 [Msun] */
    const double chi1_in,               /**< aligned-spin of companion 1 */
    const double chi2_in               /**< aligned-spin of companion 2 */
) {
    // Ensure that m1 > m2 and that chi1 is the spin on m1
    double chi1, chi2, m1, m2;
    if (m1_in>m2_in) {
       chi1 = chi1_in;
       chi2 = chi2_in;
       m1   = m1_in;
       m2   = m2_in;
    } else { // swap spins and masses
       chi1 = chi2_in;
       chi2 = chi1_in;
       m1   = m2_in;
       m2   = m1_in;
    }

    const double M = m1 + m2;
    double eta = m1 * m2 / (M * M);

    if (eta > 0.25)
        PhenomInternal_nudge(&eta, 0.25, 1e-6);
    assert (eta <= 0.25 && eta > 0.0);
 //ERROR(PD_EDOM, "Unphysical eta. Must be between 0. and 0.25\n");

    double finspin = FinalSpin0815(eta, chi1, chi2);

    if (finspin < MIN_FINAL_SPIN)
          printf("Final spin and ISCO frequency of this system are small, \
                          the model might misbehave here.");

    return finspin;
}


// /**
//  * Function to return the frequency (in Hz) of the peak of the frequency
//  * domain amplitude for the IMRPhenomD model.
//  *
//  * The peak is a parameter in the PhenomD model given by Eq. 20 in 1508.07253
//  * where it is called f_peak in the paper.
//  */
// double XLALIMRPhenomDGetPeakFreq(
//     const double m1_in,                 /**< mass of companion 1 [Msun] */
//     const double m2_in,                 /**< mass of companion 2 [Msun] */
//     const double chi1_in,               /**< aligned-spin of companion 1 */
//     const double chi2_in                /**< aligned-spin of companion 2 */
// ) {
//     // Ensure that m1 > m2 and that chi1z is the spin on m1
//     double chi1z, chi2z, m1, m2;
//     if (m1_in>m2_in) {
//        chi1z = chi1_in;
//        chi2z = chi2_in;
//        m1   = m1_in;
//        m2   = m2_in;
//     } else { // swap spins and masses
//        chi1z = chi2_in;
//        chi2z = chi1_in;
//        m1   = m2_in;
//        m2   = m1_in;
//     }
//
//     const double M = m1 + m2;
//     const double M_sec = M * MTSUN_SI; // Conversion factor Hz -> dimensionless frequency
//
//     double eta = m1 * m2 / (M * M);
//     if (eta > 0.25 || eta < 0.0)
//       ERROR(PD_EDOM, "Unphysical eta. Must be between 0. and 0.25\n");
//
//     // Calculate phenomenological parameters
//     double finspin = FinalSpin0815(eta, chi1z, chi2z);
//
//     if (finspin < MIN_FINAL_SPIN)
//           PRINT_WARNING("Final spin (Mf=%g) and ISCO frequency of this system are small, \
//                           the model might misbehave here.", finspin);
//     IMRPhenomDAmplitudeCoefficients *pAmp = ComputeIMRPhenomDAmplitudeCoefficients(eta, chi1z, chi2z, finspin);
//     if (pAmp) assert(0);
//
//     // PeakFreq, converted to Hz
//     double PeakFreq = ( pAmp->fmaxCalc ) / M_sec;
//
//     free(pAmp);
//
//     return PeakFreq;
// }
//
//
// // protoype
// static double PhenDPhaseDerivFrequencyPoint(double Mf, IMRPhenomDPhaseCoefficients *p, PNPhasingSeries *pn);
//
// /**
//  * Helper function to return the value of the frequency derivative of the
//  * Fourier domain phase.
//  * This is function is wrapped by IMRPhenomDPhaseDerivative and used
//  * when estimating the length of the time domain version of the waveform.
//  * unreviewed
//  */
// static double PhenDPhaseDerivFrequencyPoint(double Mf, IMRPhenomDPhaseCoefficients *p, PNPhasingSeries *pn)
// {
//
//   // split the calculation to just 1 of 3 possible mutually exclusive ranges
//
//   if (!StepFunc_boolean(Mf, p->fInsJoin))	// Inspiral range
//   {
//       double DPhiIns = DPhiInsAnsatzInt(Mf, p, pn);
// 	  return DPhiIns;
//   }
//
//   if (StepFunc_boolean(Mf, p->fMRDJoin))	// MRD range
//   {
//       double DPhiMRDval = DPhiMRD(Mf, p) + p->C2MRD;
// 	  return DPhiMRDval;
//   }
//
//   //	Intermediate range
//   double DPhiInt = DPhiIntAnsatz(Mf, p) + p->C2Int;
//   return DPhiInt;
// }
//
// /**
// * Estimates the length of the time domain IMRPhenomD signal
// * This does NOT taking into account any tapering that is used to condition the
// * Fourier domain waveform to compute the inverse Fourer transform.
// * To estimate the length we assume that the waveform only reaches the
// * the highest physics frequency i.e. the ringdown frequency.
// * unreviewed
// */
// double XLALSimIMRPhenomDChirpTime(
//     const double m1_SI,                 /**< Mass of companion 1 (kg) */
//     const double m2_SI,                 /**< Mass of companion 2 (kg) */
//     const double chi1_in,               /**< aligned-spin of companion 1 */
//     const double chi2_in,               /**< aligned-spin of companion 2 */
//     const double fHzSt                  /**< arbitrary starting frequency in Hz */
// ) {
//
//     if (fHzSt <= 0) ERROR(PD_EDOM, "fHzSt must be positive\n");
//
//     if (chi1_in > 1.0 || chi1_in < -1.0 || chi2_in > 1.0 || chi2_in < -1.0)
//       ERROR(PD_EDOM, "Spins outside the range [-1,1] are not supported\n");
//
//     /* external: SI; internal: solar masses */
//     const double m1_in = m1_SI / MSUN_SI;
//     const double m2_in = m2_SI / MSUN_SI;
//
//     double chi1z, chi2z, m1, m2;
//     if (m1_in>m2_in) {
//        chi1z = chi1_in;
//        chi2z = chi2_in;
//        m1   = m1_in;
//        m2   = m2_in;
//     } else { // swap spins and masses
//        chi1z = chi2_in;
//        chi2z = chi1_in;
//        m1   = m2_in;
//        m2   = m1_in;
//     }
//
//     // check that starting frequency is not higher than the peak frequency
//     const double fHzPeak = XLALIMRPhenomDGetPeakFreq(m1, m2, chi1z, chi2z);
//     if (fHzSt > fHzPeak){
//         PRINT_WARNING("Starting frequency = %f Hz is higher IMRPhenomD peak frequency %f Hz. Results may be unreliable.", fHzSt, fHzPeak);
//     }
//
//     int status = init_useful_powers(&powers_of_pi, PI);
//     if (1 == status) assert(0); //, status, "Failed to initiate useful powers of pi.");
//
//     const double M = m1 + m2;
//     const double eta = m1 * m2 / (M * M);
//
//     if (eta > 0.25 || eta < 0.0)
//       ERROR(PD_EDOM, "Unphysical eta. Must be between 0. and 0.25\n");
//
//     // compute geometric frequency
//     const double M_sec = M * MTSUN_SI;
//     const double MfSt = M_sec * fHzSt;
//
//     // Calculate phenomenological parameters
//     const double finspin = FinalSpin0815(eta, chi1z, chi2z); //FinalSpin0815 - 0815 is like a version number
//
//     if (finspin < MIN_FINAL_SPIN)
//             PRINT_WARNING("Final spin (Mf=%g) and ISCO frequency of this system are small, \
//                             the model might misbehave here.", finspin);
//     IMRPhenomDPhaseCoefficients *pPhi = ComputeIMRPhenomDPhaseCoefficients(eta, chi1z, chi2z, finspin);
//     if (pPhi) assert(0);
//     PNPhasingSeries *pn = NULL;
//     TaylorF2AlignedPhasing(&pn, m1, m2, chi1z, chi2z);
//     if (!pn) assert(0);
//
//     // Subtract 3PN spin-spin term below as this is in LAL's TaylorF2 implementation
//     // (LALSimInspiralPNCoefficients.c -> XLALSimInspiralPNPhasing_F2), but
//     // was not available when PhenomD was tuned.
//     pn->v[6] -= (Subtract3PNSS(m1, m2, M, chi1z, chi2z) * pn->v[0]);
//
//
//     PhiInsPrefactors phi_prefactors;
//     status = init_phi_ins_prefactors(&phi_prefactors, pPhi, pn);
//     if (1 == status) assert(0); //, status, "init_phi_ins_prefactors failed");
//
//     // Compute coefficients to make phase C^1 continuous (phase and first derivative)
//     ComputeIMRPhenDPhaseConnectionCoefficients(pPhi, pn, &phi_prefactors);
//
//     // We estimate the length of the time domain signal (i.e., the chirp time)
//     // By computing the difference between the values of the Fourier domain
//     // phase derivative at two frequencies.
//     // Here the starting frequency is an input i.e., fHzSt, converted to Geometric units MfSt
//     // and the ending frequency is fixed to be the frequency of the amplitude peak in Geometric units MfPeak
//     // XLALIMRPhenomDGetPeakFreq output is in Hz, covert to Mf via / M_sec
//     const double MfPeak = XLALIMRPhenomDGetPeakFreq(m1, m2, chi1z, chi2z) / M_sec;
//
//     // Compute phase derivative at starting frequency
//     const double dphifSt = PhenDPhaseDerivFrequencyPoint(MfSt, pPhi, pn);
//     // Compute phase derivative at ending (ringdown) frequency
//     const double dphifRD = PhenDPhaseDerivFrequencyPoint(MfPeak, pPhi, pn);
//     const double dphidiff = dphifRD - dphifSt;
//
//     // The length of time is estimated as dphidiff / 2 / pi * M (In units of seconds)
//     const double ChirpTimeSec = dphidiff / 2. / PI * M_sec;
//
//     free(pPhi);
//     free(pn);
//
//     return ChirpTimeSec;
//
// }
//
// /**
// * Function to return the final spin (spin of the remnant black hole)
// * as predicted by the IMRPhenomD model. The final spin is calculated using
// * the phenomenological fit described in PhysRevD.93.044006 Eq. 3.6.
// * unreviewed
// */
// double XLALSimIMRPhenomDFinalSpin(
//     const double m1_in,                 /**< mass of companion 1 [Msun] */
//     const double m2_in,                 /**< mass of companion 2 [Msun] */
//     const double chi1_in,               /**< aligned-spin of companion 1 */
//     const double chi2_in               /**< aligned-spin of companion 2 */
// ) {
//     // Ensure that m1 > m2 and that chi1z is the spin on m1
//     double chi1z, chi2z, m1, m2;
//     if (m1_in>m2_in) {
//        chi1z = chi1_in;
//        chi2z = chi2_in;
//        m1   = m1_in;
//        m2   = m2_in;
//     } else { // swap spins and masses
//        chi1z = chi2_in;
//        chi2z = chi1_in;
//        m1   = m2_in;
//        m2   = m1_in;
//     }
//
//     const double M = m1 + m2;
//
//     double eta = m1 * m2 / (M * M);
//     if (eta > 0.25 || eta < 0.0)
//       ERROR(PD_EDOM, "Unphysical eta. Must be between 0. and 0.25\n");
//
//     double finspin = FinalSpin0815(eta, chi1z, chi2z);
//
//     if (finspin < MIN_FINAL_SPIN)
//           PRINT_WARNING("Final spin (Mf=%g) and ISCO frequency of this system are small, \
//                           the model might misbehave here.", finspin);
//
//     return finspin;
// }
