"""Build figures and a Spanish summary directly from completed trial CSVs."""
from pathlib import Path
import csv
import json
import platform
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent
METHODS = ["phase_gradient", "directional_phase", "reverberant"]
LABELS = ["Gradiente de fase", "Direccional", "AIA con modelo conocido"]
COLORS = ["#2563eb", "#d97706", "#059669"]
CASES = ["planar", "strong_reflection", "scalar2d_diffuse", "axial_shear3d_xy"]
CASE_LABELS = ["Onda plana", "Reflexión fuerte", "Difuso planar 2D", "Corte difuso 3D"]
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10,
                     "axes.spines.top": False, "axes.spines.right": False})


def rows(path):
    with (ROOT / path).open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def number(row, key):
    return float(row[key])


def save(figure, name):
    figure.savefig(ROOT / (name + ".png"), dpi=180, facecolor="white")
    figure.savefig(ROOT / (name + ".svg"), facecolor="white")
    plt.close(figure)


def speed_figures(aggregate, before):
    figure, axes = plt.subplots(2, 4, figsize=(16, 7.8), sharex=True)
    snrs = [0, 5, 10, 20, np.inf]
    for column, case in enumerate(CASES):
        for method, label, color in zip(METHODS, LABELS, COLORS):
            current = [next(r for r in aggregate if r["group"] == "main" and r["case_name"] == case
                            and r["method"] == method and number(r, "snr_db") == snr) for snr in snrs]
            errors = np.array([number(r, "error_median_pct") for r in current])
            lo = np.array([number(r, "error_min_pct") for r in current])
            hi = np.array([number(r, "error_max_pct") for r in current])
            axes[0, column].plot(range(5), errors, color=color, marker="o", label=label)
            axes[0, column].fill_between(range(5), lo, hi, color=color, alpha=.13)
            coverage = [number(r, "coverage_median_pct") for r in current]
            axes[1, column].plot(range(5), coverage, color=color, marker="o")
            axes[1, column].fill_between(range(5), [number(r, "coverage_min_pct") for r in current],
                                         [number(r, "coverage_max_pct") for r in current], color=color, alpha=.13)
        axes[0, column].set_title(CASE_LABELS[column], fontweight="bold")
        axes[0, column].set_ylim(bottom=0)
        axes[1, column].set_ylim(0, 42)
        axes[1, column].axhline(100*37**2/61**2, color="#94a3b8", ls=":", lw=.8)
        for axis in axes[:, column]:
            axis.grid(alpha=.2)
            axis.set_xticks(range(5), ["0", "5", "10", "20", "Sin\nruido"])
        axes[1, column].set_xlabel("SNR temporal (dB)")
    axes[0, 0].set_ylabel("Error absoluto relativo mediano (%)")
    axes[1, 0].set_ylabel("Cobertura del campo completo (%)")
    figure.suptitle("Robustez de velocidad · 80 realizaciones independientes", fontsize=18, y=.98)
    handles, labels = axes[0, 0].get_legend_handles_labels()
    figure.legend(handles, labels, loc="upper center", bbox_to_anchor=(.5, .935), ncol=3, frameon=False)
    figure.text(.5, .01, "Línea: mediana entre 4 semillas; banda: mínimo–máximo, sin interpretación de intervalo de confianza.\n"
                "El error usa píxeles aceptados. Gradiente sin soporte en campos mezclados: no hay curva de error.", ha="center", fontsize=10)
    figure.tight_layout(rect=(0, .06, 1, .88))
    save(figure, "speed_robustness")

    figure, axis = plt.subplots(figsize=(10, 5.8))
    snrs = [0, 10, np.inf]
    def control(table, snr):
        return next(r for r in table if r["group"] == "null" and r["case_name"] == "uniform_harmonic"
                    and r["method"] == "directional_phase" and number(r,"snr_db") == snr)
    old = [number(control(before,s),"null_false_positive_median_pct") for s in snrs]
    new = [number(control(aggregate,s),"null_false_positive_median_pct") for s in snrs]
    x=np.arange(3)
    axis.bar(x-.18, old, .36, color="#dc2626", label="Antes de la corrección")
    axis.bar(x+.18, new, .36, color="#059669", label="Después de la corrección")
    for i,(a,b) in enumerate(zip(old,new)):
        axis.text(i-.18,a+.7,f"{a:.2f}%",ha="center",fontsize=11)
        axis.text(i+.18,b+.7,f"{b:.2f}%",ha="center",fontsize=11)
    axis.set_xticks(x,["Uniforme + ruido 0 dB","Uniforme + ruido 10 dB","Uniforme sin ruido"])
    axis.set_ylim(0,48);axis.set_ylabel("Campo incorrectamente aceptado (%)")
    axis.set_title("Control sin propagación · fuga espectral direccional corregida",fontsize=15,pad=17)
    axis.legend(frameon=False);axis.grid(axis="y",alpha=.2)
    figure.text(.5,.02,"Medianas entre 4 semillas. Estos controles no tienen velocidad física identificable.",ha="center",fontsize=10)
    figure.tight_layout(rect=(0,.06,1,1));save(figure,"directional_null_comparison")


def fdtd_figure(metrics):
    figure, axes = plt.subplots(1,2,figsize=(12.5,5.5))
    current = [r for r in metrics if r["method"] == "directional_phase" and "courant_0.85" in r["case_name"]]
    current.sort(key=lambda r: float(r["case_name"].split("_")[2][:-2]))
    cells=[float(r["case_name"].split("_")[2][:-2]) for r in current]
    error=[number(r,"common_absolute_error_pct") for r in current]
    old=[number(r,"baseline_common_absolute_error_pct") for r in current]
    axes[0].plot(cells,old,"o-",color="#64748b",label="Gradiente original, mismos píxeles")
    axes[0].plot(cells,error,"o-",color=COLORS[1],label="Direccional corregido")
    for x,y in zip(cells,error):axes[0].annotate(f"{y:.2f}%",(x,y),xytext=(0,9),textcoords="offset points",ha="center")
    axes[0].set_ylabel("Error absoluto relativo mediano (%)");axes[0].set_ylim(0,11);axes[0].legend(frameon=False,fontsize=9)
    axes[1].plot(cells,[number(r,"coverage_pct") for r in current],"o-",color=COLORS[1])
    for x,r in zip(cells,current):axes[1].annotate(f"{int(number(r,'common_support_pixels'))} píxeles",(x,number(r,"coverage_pct")),
                                                 xytext=(0,10),textcoords="offset points",ha="center")
    axes[1].set_ylabel("Cobertura de la ROI física (%)");axes[1].set_ylim(0,110)
    for axis in axes:axis.set_xlabel("Celda FDTD (mm)");axis.set_xticks(cells);axis.grid(alpha=.2)
    figure.suptitle("FDTD sin contacto · sensibilidad a la malla",fontsize=17)
    figure.text(.5,.01,"Referencia continua Rayleigh 1,912581 m/s; no es ground truth exacto del dominio finito.\n"
                "El soporte es común dentro de cada comparación de métodos; las tres mallas tienen muestreos distintos.",ha="center",fontsize=10)
    figure.tight_layout(rect=(0,.08,1,.94));save(figure,"fdtd_validation")


def experimental_figures(experimental):
    planes=["raster_offset_0p00mm","raster_offset_0p10mm","raster_offset_0p25mm"]
    labels=["Superficie propuesta","+0,10 mm","+0,25 mm"]
    configs=[("directional_phase","scalar2d"),("reverberant","scalar2d"),("reverberant","shear3d")]
    titles=["Direccional 0°","AIA planar","AIA corte 3D"]
    figure,axes=plt.subplots(3,3,figsize=(12,10))
    windows=[.8,1.2,1.8];coherences=[.2,.4,.6]
    for i,plane in enumerate(planes):
        for j,(method,model) in enumerate(configs):
            selected=[r for r in experimental if r["plane"]==plane and r["method"]==method and r["reverb_model"]==model
                      and r["variant"]=="observed" and r["roi"]=="early_2to4ms"]
            values=np.array([[100*number(next(r for r in selected if number(r,"min_coherence")==c
                                              and number(r,"window_x_mm")==w),"map_coverage_fraction") for w in windows] for c in coherences])
            axis=axes[i,j];im=axis.imshow(values,vmin=0,vmax=18,cmap="YlGnBu",aspect="auto")
            for y in range(3):
                for x in range(3):axis.text(x,y,f"{values[y,x]:.2f}",ha="center",va="center",
                                           color="white" if values[y,x]>10 else "#0f172a")
            axis.set_xticks(range(3),windows);axis.set_yticks(range(3),coherences)
            axis.add_patch(plt.Rectangle((.5,-.5),1,1,fill=False,edgecolor="#dc2626",lw=2))
            axis.set_xlabel("Ventana X/Y (mm)");axis.set_ylabel("Coherencia mínima")
            axis.set_title(labels[i]+" · "+titles[j],fontsize=11)
    figure.suptitle("Raster experimental · cobertura aceptada (%) · intervalo 2–4 ms",fontsize=16,y=.985)
    figure.subplots_adjust(top=.91,bottom=.15,left=.08,right=.91,hspace=.6,wspace=.4)
    colorAxis=figure.add_axes([.94,.23,.015,.53]);figure.colorbar(im,cax=colorAxis,label="Cobertura (%)")
    figure.text(.5,.018,"Rojo: parámetros de referencia predeclarados. La cobertura mide soporte, sin ground truth experimental.\n"
                "Superficie anatómica y repetibilidad de fase sin verificar; no se calculó Young experimental.",ha="center",fontsize=10)
    save(figure,"experimental_parameter_sensitivity")


def summary(aggregate, trials, experiment, metrics, mesh, young, regression):
    main=[r for r in aggregate if r["group"]=="main" and number(r,"snr_db")==5]
    main_text=[]
    for case,label,method in zip(CASES,CASE_LABELS,["phase_gradient","directional_phase","reverberant","reverberant"]):
        r=next(r for r in main if r["case_name"]==case and r["method"]==method)
        main_text.append(f"| {label} | {method} | {number(r,'error_median_pct'):.2f} [{number(r,'error_min_pct'):.2f}–{number(r,'error_max_pct'):.2f}] | {number(r,'coverage_median_pct'):.2f} |")
    fdtd_text=[]
    for r in metrics:
        if r["method"]=="directional_phase":
            fdtd_text.append(f"| {r['case_name']} | {number(r,'common_absolute_error_pct'):.2f} | {number(r,'baseline_common_absolute_error_pct'):.2f} | {number(r,'coverage_pct'):.2f} | {int(number(r,'common_support_pixels'))} |")
    experimental_text=[]
    reference=[r for r in experiment if r["variant"]=="observed" and r["roi"]=="early_2to4ms"
               and number(r,"min_coherence")==.2 and number(r,"window_x_mm")==1.2]
    for r in reference:
        experimental_text.append(f"| {r['plane']} | {r['method']} / {r['reverb_model']} | {100*number(r,'map_coverage_fraction'):.3f} | {number(r,'speed_median_m_s'):.3f} |")
    nulls=[r for r in experiment if r["variant"]!="observed"]
    max_null=max(number(r,"map_coverage_fraction") for r in nulls)*100
    failures=[r for r in regression if r["status"]=="FAIL"]
    guards=rows("speed_robustness/speed_input_guards.csv")
    final_null=max(number(r,"null_false_positive_max_pct") for r in aggregate if r["group"]=="null")
    shared=next(r for r in mesh if r["case_name"]=="fdtd_cell_0.15mm_courant_0.85" and r["method"]=="directional_phase")
    text=f"""# Resumen de validación ampliada de OCE

Fecha de cierre: **2026-10-05**, America/Lima. Se conservaron mapas numéricos sin suavizar, máscaras de rechazo, parámetros, registros y scripts de reproducción. El nombre de la carpeta de resultados es `results`.

## Hallazgos principales

- El control sin propagación reveló fuga espectral del filtro direccional. Se corrigió eliminando el promedio espacial complejo antes del padding y referenciando la amplitud al movimiento medido. En los **16 controles sintéticos**, el máximo soporte falso final fue **{final_null:.2f}%** para los tres métodos. Esto cubre los controles ensayados, no garantiza rechazo universal.
- En FDTD, el método direccional conserva aproximadamente **2,8%** de error mediano en las mallas de 0,10 y 0,15 mm. En la malla de 0,15 mm el gradiente original tiene **7,61%** sobre los mismos 209 píxeles.
- La elección del método sigue dependiendo del campo: el gradiente es muy preciso para ondas planas; AIA supera al direccional en el campo de corte difuso 3D. No hay un método ganador universal.
- La inversión A0 libre recuperó sus referencias bajo el modelo conocido. Aplicar Rayleigh a A0 generó errores de **{young['wrong_rayleigh_min_error_pct']:.2f}% a {young['wrong_rayleigh_max_error_pct']:.2f}%**. El umbral `kh≤0,6` de la aproximación delgada aceptó 7/54 referencias y permitió hasta **{young['thin_gate_max_abs_error_pct']:.2f}%** de error.
- Los planos experimentales continúan con soporte localizado y dependiente de parámetros. A +0,25 mm no se aceptaron velocidades en los barridos. La superficie y la sincronización espacial siguen sin verificar.

## Alcance y archivos

| Estudio | Casos / evaluaciones finales | Artefactos |
| --- | ---: | --- |
| Velocidad estocástica | 80 realizaciones principales + 8 con huecos + 16 controles; 312 ejecuciones de método | [CSV por realización](speed_robustness/speed_robustness_trials.csv), [resumen detallado](speed_robustness/hallazgos_velocidad.md) |
| Frecuencia suministrada | 5 frecuencias × 3 métodos = 15 evaluaciones | [CSV](speed_robustness/frequency_detuning_probe.csv) |
| FDTD sin contacto | 3 mallas + 1 paso temporal alternativo; 12 estimaciones nuevas y 24 originales | [métricas](fdtd_resolution/estimator_metrics.csv), [coordenadas comunes](fdtd_resolution/mesh_common_coordinates.csv), [configuración](fdtd_resolution/fdtd_settings.json) |
| Young | 90 referencias físicas, incluidas 54 A0; 234 conversiones y 1296 perturbaciones de entrada | [modelos](young_sensitivity/young_model_comparison.csv), [sensibilidad](young_sensitivity/young_input_sensitivity.csv) |
| Datos experimentales | 180 barridos de parámetros + 20 perturbaciones de control | [CSV](experimental_sensitivity/experimental_sensitivity_trials.csv) |
| Regresión del repositorio | {sum(r['status']=='PASS' for r in regression)} PASS, {len(failures)} FAIL preexistentes | [resultados](regression_results.csv), [registro](regression.log) |

Las evaluaciones que reutilizan un mismo campo o plano no son adquisiciones independientes. El número de ejecuciones no constituye una medida de evidencia estadística. Los resultados anteriores a la corrección están conservados en `before_directional_fix`; los de la validación inicial están en `previous_validation` y no se mezclan con los mapas finales.

## Velocidad: ruido, mezcla de ondas y soporte

Campos homogéneos independientes con `c=2 m/s`, `f=1000 Hz`, cuatro semillas, 61×61 posiciones a 100 µm y 80 tiempos a 50 µs. El SNR temporal usa RMS del movimiento limpio dividido por la desviación del ruido gaussiano. Ventana 2,4×2,4 mm; máximo lag AIA 1 mm. Con la ventana completa, la cobertura máxima del campo es 36,79%; los bordes cuentan como rechazo. Se corrigió también el redondeo flotante al resolver ventanas y lags exactamente enteros.

Ejemplo a **SNR 5 dB**, mediana entre semillas; rango de las medianas de error entre corchetes:

| Campo | Método ilustrado | Error absoluto mediano % [mín–máx] | Cobertura mediana % |
| --- | --- | ---: | ---: |
{chr(10).join(main_text)}

![Robustez y cobertura](speed_robustness.png)

![Referencia, estimado y error](speed_examples.png)

Los métodos ilustrados corresponden a hipótesis explícitas; todas las combinaciones de método/campo se conservan en los CSV. El error se calcula sobre la máscara aceptada; una cobertura menor puede reducirlo. Las bandas son mínimo–máximo entre cuatro semillas, no intervalos de confianza. Los huecos medidos permanecen NaN.

![Control de movimiento uniforme](directional_null_comparison.png)

Los tres guardas de entrada (Nyquist temporal, menos de un ciclo, rango de velocidad descendente) rechazaron las solicitudes inválidas. Un control espacial ya aliasado devolvió una velocidad aparente distinta de la física: el mapa por sí solo no identifica de manera única ese alias. En la prueba de frecuencia, suministrar 1100 Hz a una onda de 1000 Hz desplazó la velocidad aproximadamente 10%, aun con ajuste temporal alto. Revisar frecuencia y muestreo forma parte de la interpretación.

## FDTD: resolución espacial y temporal

Simulador de Claude sin modificaciones: material elástico homogéneo de 12 kPa, ν=0,495, ρ=1000 kg/m³, superficie libre, pulso gaussiano sin contacto y dominio 9×3,4×4 mm. Se mantuvo 1,2 mm de espesor físico PML. Celdas 0,20/0,15/0,10 mm, Courant 0,85; un caso adicional a 0,15 mm usa Courant 0,50. Se muestreó 8 ms a 40 µs, derivó el desplazamiento axial y analizó 1 kHz con ventana 1,5 mm.

| Caso | Error direccional % | Error original sobre soporte común % | Cobertura % | Píxeles comunes |
| --- | ---: | ---: | ---: | ---: |
{chr(10).join(fdtd_text)}

![Malla FDTD](fdtd_validation.png)

![Mapas direccionales FDTD](fdtd_resolution/directional_maps.png)

La diferencia mediana absoluta direccional entre 0,15 y 0,10 mm, interpolando exclusivamente para comparar coordenadas físicas comunes, fue **{number(shared,'median_absolute_difference_to_0p10mm_pct'):.3f}%** en {int(number(shared,'common_coordinate_count'))} coordenadas. El resultado numérico no se rellena. La reducción de Courant produjo cambios muy pequeños en las medianas, que se conservan en el CSV. AIA no aceptó velocidades en la malla de 0,20 mm con estos parámetros.

Esta es una prueba de sensibilidad, sin extrapolación Richardson ni orden de convergencia demostrado. La referencia de 1,912581 m/s corresponde al semiespacio continuo, no a la solución exacta del dominio finito. Las mallas tienen distintos muestreos y ventanas discretas realizadas.

## Young: modelo conocido y sensibilidad de entrada

Se generaron 54 referencias A0 mediante una ecuación secular forward independiente: E=3/12/30 kPa, h=0,1/0,3/1 mm, f=300/1000/2000 Hz, ν=0,45/0,495. Se añadieron 36 referencias Rayleigh/corte. No se generó la referencia con la función de inversión. El error numérico máximo del modelo correcto fue **{young['exact_max_abs_error_pct']:.3g}%**. Es una verificación bajo un modelo ideal conocido, no una estimación de exactitud experimental.

![Elección del modelo](young_sensitivity/young_model_bias.png)

![Sensibilidad de Young](young_sensitivity/young_input_sensitivity.png)

En A0, sobreestimar la velocidad un 5% produjo errores de Young de **{young['speed_sensitivity_a0']['5'][0]:.2f}% a {young['speed_sensitivity_a0']['5'][2]:.2f}%**; un +10% produjo **{young['speed_sensitivity_a0']['10'][0]:.2f}% a {young['speed_sensitivity_a0']['10'][2]:.2f}%**. La densidad transmite su error aproximadamente de forma lineal. Espesor y Poisson también afectan la conversión; se rechazaron 90 perturbaciones de Poisson no físicas. Las bandas de las figuras describen escenarios deterministas, no incertidumbre medida. No se aplicó este cálculo a los BIN experimentales.

## Experimentos: sensibilidad y controles

Se reutilizaron los cuatro planos de movimiento guardados de los BIN suministrados; no se releyó el raster de 16,4 GB. Frecuencias nominales externas: Luis3 1 kHz, raster 2 kHz. Se compararon intervalo completo y 2–4 ms; coherencia 0,2/0,4/0,6; ventanas 0,8/1,2/1,8 mm. Para B-mode la ventana axial fue 0,08 mm. No se optimizaron estos valores contra una verdad experimental inexistente.

Referencia predeclarada: 2–4 ms, coherencia 0,2, ventana lateral 1,2 mm:

| Plano | Método / modelo | Cobertura % | Velocidad mediana m/s |
| --- | --- | ---: | ---: |
{chr(10).join(experimental_text)}

![Mapas por profundidad](experimental_depth_maps.png)

![Sensibilidad de parámetros](experimental_parameter_sensitivity.png)

Los CSV guardan IoU, retención de píxeles y cambios de velocidad en soporte compartido respecto de la referencia del mismo método/modelo. Una IoU alta mide estabilidad, no exactitud. Se ensayaron shuffle temporal común y reemplazo de la fase armónica por fases independientes conservando amplitud/residuo. El máximo soporte aceptado de estas 20 perturbaciones fue **{max_null:.3f}%**; son diagnósticos de semilla fija, no p-values. Los supuestos de superficie y repetibilidad permanecen abiertos. En los registros cortos, una coherencia mayor puede reflejar también ajuste de ruido.

## Regresión, procedencia y reproducción

Regresión canónica con `UpdateBaseline=false`: **{sum(r['status']=='PASS' for r in regression)} aprobadas, {len(failures)} fallos preexistentes, 0 omitidas**. Los fallos son el inventario MIMT (151 esperados/144 presentes) y el contrato de vídeo filtrado (test espera false, workflow previo true). No se alteraron goldens ni tolerancias para ocultarlos. La regresión local incluye ahora el movimiento uniforme direccional y el redondeo de lags.

MATLAB R2025b, CPU, `-singleCompThread`; Python {platform.python_version()}, NumPy {np.__version__}, Matplotlib {matplotlib.__version__}. [source_hashes.csv](source_hashes.csv) identifica los propietarios científicos al cierre. Los datos BIN originales se conservaron. Los scripts son validación observacional guardada en `results`, no nuevos tests redundantes del catálogo.

Desde MATLAB, configure el directorio de esta validación y ejecute:

```matlab
validationRoot = '{ROOT.as_posix()}';
workflowRoot = fileparts(fileparts(validationRoot));
run(fullfile(workflowRoot,'startup.m'));
addpath(validationRoot,fullfile(validationRoot,'speed_robustness'), ...
    fullfile(validationRoot,'young_sensitivity'),fullfile(validationRoot,'fdtd_resolution'));
run_speed_robustness_validation;
run_frequency_detuning_probe;
run_young_sensitivity;
run(fullfile(validationRoot,'experimental_sensitivity','run_experimental_sensitivity.m'));
run_fdtd_evaluation;
export_validation_maps;
```

Los generadores Python `young_sensitivity/generate_young_reference_cases.py` y `fdtd_resolution/run_fdtd_resolution.py` usan el entorno del simulador. El segundo vuelve a ejecutar las cuatro simulaciones. `render_validation_summary.py` reconstruye las figuras y este resumen desde CSV; `young_sensitivity/render_young_sensitivity.py` reconstruye las figuras de Young. Consulte cada cabecera para paths de entrada y requisitos.
"""
    (ROOT/"Resumen_validacion.md").write_text(text,encoding="utf-8")
    metadata=dict(date="2026-10-05",timezone="America/Lima",synthetic_realizations=len(set(r['trial_id'] for r in trials)),
                  synthetic_method_runs=len(trials),experimental_runs=len(experiment),experimental_null_runs=len(nulls),
                  young_reference_cases=young['reference_cases'],young_model_runs=young['model_comparison_rows'],
                  young_perturbation_runs=young['sensitivity_rows'],fdtd_cases=4,regression_pass=sum(r['status']=='PASS' for r in regression),
                  regression_fail=len(failures),final_max_synthetic_null_coverage_pct=final_null,
                  max_experimental_null_coverage_pct=max_null,production_fix="remove directional common spatial motion; measured amplitude reference; ULP-tolerant integer spatial spans")
    (ROOT/"summary_statistics.json").write_text(json.dumps(metadata,indent=2),encoding="utf-8")
    print(json.dumps(metadata,indent=2))


def main():
    aggregate=rows("speed_robustness/speed_robustness_aggregate.csv")
    trials=rows("speed_robustness/speed_robustness_trials.csv")
    before=rows("before_directional_fix/speed_robustness/speed_robustness_aggregate.csv")
    experiment=rows("experimental_sensitivity/experimental_sensitivity_trials.csv")
    metrics=rows("fdtd_resolution/estimator_metrics.csv")
    mesh=rows("fdtd_resolution/mesh_common_coordinates.csv")
    young=json.loads((ROOT/"young_sensitivity/summary_statistics.json").read_text(encoding="utf-8"))
    regression=rows("regression_results.csv")
    speed_figures(aggregate,before);fdtd_figure(metrics);experimental_figures(experiment)
    summary(aggregate,trials,experiment,metrics,mesh,young,regression)
    print("VALIDATION_SUMMARY_RENDERED")


if __name__ == "__main__":
    main()
