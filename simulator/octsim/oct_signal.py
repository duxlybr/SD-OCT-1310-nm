"""Señal OCT compleja simulada (dominio de profundidad, después de la FFT).

Modelo de A-scan [IzattChoma2008]:
    A(d) = sum_s a_s h(d - d_s) exp(i 2 k0 d_s) + ruido,
con d el camino óptico (OPL) de ida desde el retardo cero, h la envolvente
axial (gaussiana de FWHM = resolución axial medida) y k0 = 2 pi / lambda0.

* Speckle totalmente desarrollado: amplitudes complejas gaussianas circulares
  [Schmitt1999]; la potencia media por celda sigue la retrodispersión del
  material, la atenuación de doble paso exp(-2 mu z) [Faber2004] y el roll-off
  medido del espectrómetro (-3.32 dB/mm) [repo:LATEST].
* Interfaces: reflexión especular de Fresnel R = ((n1 - n2)/(n1 + n2))^2
  [BornWolf1999], atenuada por la inclinación local respecto de la divergencia
  del haz gaussiano theta0 = lambda0/(pi W0) [SalehTeich2007] (supuesto).
* SNR: la sensibilidad medida (79.6 dB) es la SNR de un reflector perfecto en
  el retardo cero [repo:LATEST]; el ruido es gaussiano complejo de potencia 1.
* Ruido de fase común por A-line con sigma = 0.636 mrad (estabilidad de fase
  medida) [repo:LATEST]; el ruido aditivo produce además sigma_phi ~ 1/sqrt(SNR)
  [Choma2005; Singh2022, Ec. (17)].

Movimiento -> fase. Con desplazamiento u_z(z, t) (positivo hacia +z, lejos de la
sonda) el cambio de camino óptico de un dispersor a profundidad z es
    dOPL(z) = n(z) u(z) - sum_{interfaces j sobre z} (n_debajo_j - n_encima_j) u(z_j),
que para una sola interfaz aire/tejido da n u(z) - (n - 1) u_superficie: el
artefacto de movimiento de superficie por desajuste de índice descrito en
[Song2013]. La fase es phi = 4 pi dOPL / lambda0, consistente con
dz = dphi lambda / (4 pi n) [Nguyen2014, Ec. (1)] para superficie fija. La
envolvente se desplaza a primer orden: A0(d - dOPL) ~ A0(d) - dOPL A0'(d)
(válido si |dOPL| << resolución axial; se advierte si no se cumple).
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, fields
from math import log, pi, sqrt
from typing import Any

import numpy as np

from .acquisition import AcquisitionPlan
from .excitation import ExcitationConfig
from .fdtd import FieldRecord
from .geometry import AIR_ID, Geometry


@dataclass
class OCTSystem:
    """Parámetros del SD-OCT 1310 nm medidos en la campaña 2026-09 [repo:LATEST]."""

    lambda0_nm: float = 1317.97
    axial_res_um: float = 9.65          # FWHM en aire
    lateral_res_um: float = 11.04
    depth_px_um: float = 5.931          # muestra nativa (FFT de 2048, sin relleno)
    sensitivity_db: float = 79.6
    rolloff_db_per_mm: float = -3.32
    phase_stability_mrad: float = 0.636
    zero_delay_gap_mm: float = 0.30     # aire entre el retardo cero y el ápice de la muestra
    depth_window_mm: float = 1.2        # profundidad óptica simulada bajo el ápice
    specular: bool = True
    trigger_jitter_us: float = 0.0
    seed: int = 7

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "OCTSystem":
        known = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in d.items() if k in known})

    @property
    def k0_per_mm(self) -> float:
        return 2 * pi / (self.lambda0_nm * 1e-6)

    @property
    def dz_mm(self) -> float:
        return self.depth_px_um * 1e-3

    def displacement_sensitivity_pm(self, n: float = 1.0) -> float:
        """sigma_phi lambda0 / (4 pi n) [repo:LATEST; Nguyen2014, Ec. (1)]."""
        return self.phase_stability_mrad * 1e-3 * self.lambda0_nm * 1e3 / (4 * pi * n)


class OCTSimulator:
    """Genera B-scans complejos [A, Z, M] siguiendo el plan de adquisición."""

    FINE = 4   # submuestreo del speckle en profundidad

    def __init__(self, system: OCTSystem, geom: Geometry, field: FieldRecord,
                 plan: AcquisitionPlan, exc: ExcitationConfig):
        self.sys = system
        self.geom = geom
        self.field = field
        self.plan = plan
        self.exc = exc
        mats = geom.materials()
        self.n_lut = np.ones(256)
        self.rb_lut = np.full(256, -np.inf)
        self.mu_lut = np.zeros(256)
        for i, m in enumerate(mats, start=1):
            self.n_lut[i] = m.n
            self.rb_lut[i] = m.backscatter_db
            self.mu_lut[i] = m.mu_oct_per_mm
        dz = system.dz_mm
        d_lo = system.zero_delay_gap_mm - 0.1
        d_hi = system.zero_delay_gap_mm + system.depth_window_mm * max(self.n_lut[1:len(mats) + 1].max(), 1.0)
        self.bins = np.arange(int(np.floor(d_lo / dz)), int(np.ceil(d_hi / dz)) + 1)
        self.d_mm = self.bins * dz                 # OPL desde el retardo cero
        self.excitation_onsets = plan.trigger_times + exc.ch2_delay_ms * 1e-3
        self.max_shift_mm = 0.0
        w0 = system.lateral_res_um * 1e-3 / sqrt(2 * log(2))      # radio 1/e^2 desde el FWHM
        self.theta0 = system.lambda0_nm * 1e-6 / (pi * w0)        # [SalehTeich2007]

    # ----------------------------------------------------------------- ópticas
    def column_optics(self, pos: np.ndarray) -> dict[str, np.ndarray]:
        """Para cada posición (A, 2): profundidad física de cada bin, índice, potencia
        media de speckle (SNR lineal) y reflectores especulares."""
        s = self.sys
        A = pos.shape[0]
        nb = self.d_mm.size
        gap = s.zero_delay_gap_mm
        zs = self.geom.surface_z(pos[:, 0], pos[:, 1])                 # (A,)
        step = s.dz_mm / (self.FINE * 2)
        z_end = min(self.geom.size_z_mm + 0.05, float(zs.max()) + s.depth_window_mm + 0.3)
        z_f = np.arange(-0.2, z_end, step)
        ids_f = self.geom.material_id_map(pos[:, 0, None] * np.ones_like(z_f)[None, :],
                                          pos[:, 1, None] * np.ones_like(z_f)[None, :],
                                          np.broadcast_to(z_f, (A, z_f.size)))
        n_f = self.n_lut[ids_f]
        # OPL(z): aire (n = 1) desde el retardo cero (z = -gap) y luego sum n dz [IzattChoma2008]
        opl_f = gap + z_f[0] + np.concatenate((np.zeros((A, 1)), np.cumsum(n_f[:, :-1] * step, axis=1)), axis=1)
        z_b = np.empty((A, nb))
        ids_b = np.empty((A, nb), dtype=np.uint8)
        for a in range(A):
            idx = np.clip(np.searchsorted(opl_f[a], self.d_mm), 0, z_f.size - 1)
            z_b[a] = z_f[idx]
            ids_b[a] = ids_f[a, idx]
        n_b = self.n_lut[ids_b]
        # potencia de speckle (SNR lineal por bin)
        depth_below = np.maximum(z_b - zs[:, None], 0.0)
        atten_db = 10 * np.log10(np.e) * 2 * self.mu_lut[ids_b] * depth_below          # [Faber2004]
        roll_db = s.rolloff_db_per_mm * np.abs(self.d_mm)[None, :]                       # [repo:LATEST]
        snr_db = s.sensitivity_db + self.rb_lut[ids_b] + roll_db - atten_db
        snr = np.where(ids_b == AIR_ID, 0.0, 10 ** (snr_db / 10))
        # reflectores especulares en cambios de índice a lo largo de la columna
        spec = []
        if s.specular:
            tilt = self.geom.surface_normal_tilt(pos[:, 0], pos[:, 1])
            ang = np.exp(-2 * (tilt / self.theta0) ** 2)
            for a in range(A):
                change = np.nonzero(np.diff(n_f[a]) != 0)[0]
                for c in change:
                    n1, n2 = n_f[a, c], n_f[a, c + 1]
                    R = ((n1 - n2) / (n1 + n2)) ** 2                                    # [BornWolf1999]
                    d_i = opl_f[a, c + 1]
                    pw_db = s.sensitivity_db + 10 * np.log10(R * ang[a] + 1e-30) + s.rolloff_db_per_mm * d_i
                    spec.append((a, d_i, 10 ** (pw_db / 10), z_f[c + 1]))
        return {"z_b": z_b, "n_b": n_b, "ids_b": ids_b, "snr": snr, "spec": spec, "zs": zs}

    def static_ascans(self, pos: np.ndarray, optics: dict[str, np.ndarray]) -> np.ndarray:
        """A-scans complejos estáticos A0 [A, Z] (speckle + especulares)."""
        s = self.sys
        A, nb = optics["snr"].shape
        F = self.FINE
        sig = (s.axial_res_um * 1e-3) / (2 * sqrt(2 * log(2))) / (s.dz_mm / F)   # sigma en muestras finas
        kx = np.arange(-int(4 * sig) - 1, int(4 * sig) + 2)
        kern = np.exp(-0.5 * (kx / sig) ** 2)
        kern /= np.sqrt(np.sum(kern**2))
        out = np.zeros((A, nb), dtype=np.complex128)
        q = s.lateral_res_um * 1e-3 / 4
        for a in range(A):
            ix = int(np.round(pos[a, 0] / q)) + 2**20
            iy = int(np.round(pos[a, 1] / q)) + 2**20
            rng = np.random.default_rng([s.seed, ix, iy])
            amp = np.repeat(np.sqrt(optics["snr"][a]), F)
            noise = (rng.standard_normal(nb * F) + 1j * rng.standard_normal(nb * F)) / sqrt(2)
            fine = np.convolve(noise * amp, kern, mode="same")
            out[a] = fine[::F]
        # correlación lateral si las A-lines están más cerca que la PSF lateral (aprox.)
        if A > 2:
            spacing = np.median(np.linalg.norm(np.diff(pos, axis=0), axis=1))
            fw = s.lateral_res_um * 1e-3
            if 0 < spacing < fw:
                sl = fw / (2 * sqrt(2 * log(2))) / spacing
                lx = np.arange(-int(3 * sl) - 1, int(3 * sl) + 2)
                lk = np.exp(-0.5 * (lx / sl) ** 2)
                lk /= np.sqrt(np.sum(lk**2))
                out = np.apply_along_axis(lambda v: np.convolve(v, lk, mode="same"), 0, out)
        return out

    def _sample_index(self, pos: np.ndarray, z_mm: np.ndarray, zs: np.ndarray) -> np.ndarray:
        """Índice fraccional en los nodos z del registro para profundidades z_mm [A, N].

        Dentro de la muestra (z >= z_s) nunca se interpola con nodos de aire: el índice
        se acota al nodo vz de la interfaz, que se mueve con la superficie.
        """
        f = self.field
        zr = f.z_m * 1e3
        ix = np.array([np.argmin(np.abs(f.x_m * 1e3 - p)) for p in pos[:, 0]])
        iy = np.array([np.argmin(np.abs(f.y_m * 1e3 - p)) for p in pos[:, 1]])
        k_if = np.clip(f.surface_k[ix, iy], 0, zr.size - 1)
        fz = np.interp(z_mm, zr, np.arange(zr.size))
        inside = z_mm >= zs[:, None] - 1e-9
        fz = np.where(inside, np.maximum(fz, k_if[:, None]), fz)
        return np.clip(fz, 0, zr.size - 1.000001)

    # ------------------------------------------------------------- campo mecánico
    def _bilinear(self, pos: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
        f = self.field
        x = f.x_m * 1e3
        y = f.y_m * 1e3
        fx = np.clip(np.interp(pos[:, 0], x, np.arange(x.size)), 0, x.size - 1.000001)
        fy = np.clip(np.interp(pos[:, 1], y, np.arange(y.size)), 0, y.size - 1.000001) if y.size > 1 \
            else np.zeros(pos.shape[0])
        ix = np.floor(fx).astype(int)
        iy = np.floor(fy).astype(int)
        wx = fx - ix
        wy = fy - iy
        ix1 = np.minimum(ix + 1, x.size - 1)
        iy1 = np.minimum(iy + 1, y.size - 1)
        return (np.stack([ix, ix1, ix, ix1], 1), np.stack([iy, iy, iy1, iy1], 1),
                np.stack([(1 - wx) * (1 - wy), wx * (1 - wy), (1 - wx) * wy, wx * wy], 1), fx)

    def _record_index_profile(self, pos: np.ndarray) -> np.ndarray:
        """Índice de refracción en los nodos z del registro, por posición [A, nz]."""
        z = self.field.z_m * 1e3
        A = pos.shape[0]
        ids = self.geom.material_id_map(pos[:, 0, None] * np.ones((1, z.size)),
                                        pos[:, 1, None] * np.ones((1, z.size)),
                                        np.broadcast_to(z, (A, z.size)))
        return self.n_lut[ids]

    def delta_opl_columns(self, pos: np.ndarray, times: np.ndarray) -> np.ndarray:
        """dOPL(z_registro, t) [A, M, nz] en mm, para tiempos absolutos [A, M]."""
        f = self.field
        IX, IY, W, _ = self._bilinear(pos)
        A, M = times.shape
        if self.sys.trigger_jitter_us > 0:
            rng = np.random.default_rng(self.sys.seed + 5)
            times = times + rng.normal(0, self.sys.trigger_jitter_us * 1e-6, (A, 1))
        if f.regime == "transitorio":
            ucol = np.zeros((A, f.times_s.size, f.z_m.size), dtype=np.float32)
            for c in range(4):
                ucol += W[:, c, None, None] * np.moveaxis(f.uz[:, IX[:, c], IY[:, c], :], 1, 0)
            dt = f.times_s[1] - f.times_s[0]
            tmax = f.times_s[-1]
            # desvanecimiento coseno en el último tramo simulado: evita un escalón artificial
            # cuando la respuesta de un disparo anterior sale de la ventana sin haberse
            # extinguido (supuesto explícito; ver la advertencia de vibración residual)
            fade = min(0.5e-3, 0.2 * tmax)
            onsets = self.excitation_onsets
            u = np.zeros((A, M, f.z_m.size), dtype=np.float64)
            last = np.searchsorted(onsets, times, side="right") - 1          # [A, M]
            for back in range(0, 64):
                j = last - back
                valid = j >= 0
                if not valid.any():
                    break
                trel = times - onsets[np.clip(j, 0, None)]
                valid &= (trel >= 0) & (trel <= tmax)
                if not valid.any():
                    if (trel > tmax).all():
                        break
                    continue
                fi = np.clip(trel / dt, 0, f.times_s.size - 1.000001)
                i0 = np.floor(fi).astype(int)
                w = (fi - i0)[..., None]
                aa = np.arange(A)[:, None]
                val = (1 - w) * ucol[aa, i0] + w * ucol[aa, np.minimum(i0 + 1, f.times_s.size - 1)]
                taper = np.where(trel > tmax - fade,
                                 0.5 * (1 + np.cos(np.pi * np.clip((trel - (tmax - fade)) / fade, 0, 1))), 1.0)
                u += np.where(valid[..., None], val * taper[..., None], 0.0)
        else:
            w0 = 2 * pi * f.freq_hz
            u = np.zeros((A, M, f.z_m.size), dtype=np.float64)
            for h, Uh in f.U.items():
                col = np.zeros((A, f.z_m.size), dtype=np.complex128)
                for c in range(4):
                    col += W[:, c, None] * Uh[IX[:, c], IY[:, c], :]
                u += np.real(col[:, None, :] * np.exp(1j * h * w0 * times)[..., None])
        # dOPL = n u - sum interfaces (n_debajo - n_encima) u(interfaz)   [Song2013]
        u = u * 1e3                                                          # FDTD en m -> mm
        n = self._record_index_profile(pos)                                  # [A, nz]
        dn = np.diff(np.concatenate((np.ones((A, 1)), n), axis=1), axis=1)   # n_k - n_{k-1}
        return n[:, None, :] * u - np.cumsum(dn[:, None, :] * u, axis=2)

    # ------------------------------------------------------------------ B-scan
    def bscan(self, b: int, s: int, rng: np.random.Generator) -> dict[str, np.ndarray]:
        """B-scan complejo [A, Z, M] y datos auxiliares (orden físico de posiciones)."""
        sysm = self.sys
        pos = self.plan.positions[b, s]
        times = self.plan.aline_times(b, s)                                  # [A, M]
        optics = self.column_optics(pos)
        A0 = self.static_ascans(pos, optics)                                 # [A, Z]
        dopl_rec = self.delta_opl_columns(pos, times)                        # [A, M, nzr]
        zr = self.field.z_m * 1e3
        # interpolación de dOPL a la profundidad física de cada bin
        A, nb = optics["z_b"].shape
        M = times.shape[1]
        dopl = np.empty((A, M, nb))
        FZ = self._sample_index(pos, optics["z_b"], optics["zs"])
        for a in range(A):
            fz = FZ[a]
            i0 = np.floor(fz).astype(int)
            w = fz - i0
            dopl[a] = (1 - w) * dopl_rec[a][:, i0] + w * dopl_rec[a][:, np.minimum(i0 + 1, zr.size - 1)]
        dopl = np.where(optics["snr"][:, None, :] > 0, dopl, 0.0)        # sin dispersores en aire
        self.max_shift_mm = max(self.max_shift_mm, float(np.abs(dopl).max()))
        # envolvente desplazada a primer orden + fase 4 pi dOPL / lambda0
        nu = np.fft.fftfreq(nb, sysm.dz_mm)
        dA0 = np.fft.ifft(2j * pi * nu[None, :] * np.fft.fft(A0, axis=1), axis=1)
        sig = (A0[:, None, :] - dopl * dA0[:, None, :]) * np.exp(2j * sysm.k0_per_mm * dopl)
        # reflexiones especulares: se mueven con el dOPL de su interfaz [Song2013]
        if optics["spec"]:
            env_sig = (sysm.axial_res_um * 1e-3) / (2 * sqrt(2 * log(2)))
            rng_s = np.random.default_rng([sysm.seed, 99])
            for a, d_i, pw, z_i in optics["spec"]:
                fzi = self._sample_index(pos[a:a + 1], np.array([[z_i]]), optics["zs"][a:a + 1])[0, 0]
                i0 = int(np.floor(fzi))
                w = fzi - i0
                d_s = (1 - w) * dopl_rec[a][:, i0] + w * dopl_rec[a][:, min(i0 + 1, zr.size - 1)]   # [M]
                env = np.exp(-0.5 * ((self.d_mm[None, :] - d_i - d_s[:, None]) / env_sig) ** 2)
                sig[a] += (np.sqrt(pw) * np.exp(1j * rng_s.uniform(0, 2 * pi))
                           * env * np.exp(2j * sysm.k0_per_mm * d_s)[:, None])
        # ruido de fase común por A-line y ruido aditivo complejo de potencia 1
        common = rng.normal(0, sysm.phase_stability_mrad * 1e-3, (A, M))
        sig *= np.exp(1j * common)[..., None]
        sig += (rng.standard_normal(sig.shape) + 1j * rng.standard_normal(sig.shape)) / sqrt(2)
        return {"data": np.moveaxis(sig, 2, 1).astype(np.complex64),       # [A, Z, M]
                "positions": pos, "times": times, "z_b": optics["z_b"], "n_b": optics["n_b"],
                "ids_b": optics["ids_b"], "zs": optics["zs"], "snr": optics["snr"]}

    def check_shift(self) -> str | None:
        lim = 0.25 * self.sys.axial_res_um * 1e-3
        if self.max_shift_mm > lim:
            return (f"El desplazamiento óptico máximo ({self.max_shift_mm * 1e3:.2f} um) supera 1/4 de la "
                    f"resolución axial; la aproximación de primer orden de la envolvente pierde exactitud.")
        return None
