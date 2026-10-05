# Referencia axial XZ de A0 para una placa libre homogénea

`analytic_a0_xz.py` produce un eigenmodo continuo de una placa infinita, plana, homogénea, isotrópica, lineal, sin pérdidas, pretensión ni carga de fluido. **Exacto** se refiere a ese problema y a un único modo A0, no a una inclusión, una fuerza localizada ni al contenido modal completo de FDTD.

La teoría primaria es [Lamb, On waves in an elastic plate, 1917, DOI 10.1098/rspa.1917.0008](https://doi.org/10.1098/rspa.1917.0008). Las definiciones de potenciales, desplazamiento y tracción y el papel de ambas superficies también aparecen en [Nenadic et al., 2011, DOI 10.1088/0031-9155/56/20/014](https://doi.org/10.1088/0031-9155/56/20/014); ese artículo estudia además carga fluida, que aquí se excluye explícitamente. Las fórmulas Cartesianas siguientes son una derivación independiente por Navier, no una copia de la función modal del simulador.

Sea h el espesor completo, a=h/2 y ζ=z−a, con z=0 arriba y z=h abajo. El campo físico usa `Re[U(x,z) exp(−iωt)]`, propagación +X. Para c<cs:

```text
μ=E/[2(1+ν)], λ=Eν/[(1+ν)(1−2ν)]
cs²=μ/ρ, cl²=(λ+2μ)/ρ, k=ω/c
p²=k²−ω²/cl², q²=k²−ω²/cs², D=k²+q²
φ=A sinh(pζ)/cosh(pa), ψ=B cosh(qζ)/cosh(qa)
ux=ikφ−∂zψ, uz=∂zφ+ikψ
σxz=μ(∂zux+ikuz)
σzz=λ ikux+(λ+2μ)∂zuz
```

Imponer σxz=0 en ambas caras da `B=2ikpA/D`. La tracción normal da la ecuación secular `D² tanh(pa)−4k²pq tanh(qa)=0`. La velocidad se obtiene mediante `independent_lamb_a0` del exportador independiente; se vuelve a verificar la ecuación y las tracciones en el helper, incluso cuando se proporciona c como argumento.

La forma axial resultante es

```text
uz(ζ)=A p [cosh(pζ)/cosh(pa)−(2k²/D)cosh(qζ)/cosh(qa)]
ux(ζ)=i A k [sinh(pζ)/cosh(pa)−(2pq/D)sinh(qζ)/cosh(qa)]
A=1/[p(1−2k²/D)]
U_z(x,z)=uz(ζ) exp(ikx)
```

La normalización hace `uz(0)=uz(h)=1`: desplazamiento axial par e in-plane impar respecto de la cara media, el carácter A0. Las razones hiperbólicas se evalúan con exponenciales decrecientes para evitar overflow. El retorno `phasor(...)` es `(field[nz,nx],checks)`; los puntos fuera de la placa son NaN. Para datos definidos como `Re[P exp(+iωt)]`, usar `P=conj(field)`. El fasor de **velocidad** añade un factor global `−iω` respecto del desplazamiento; una comparación de forma/fase globalmente normalizada debe declarar esa conversión.

## Verificación independiente del campo

Se evalúa la ecuación dimensional de Navier `(λ+μ)grad(div u)+μ laplacian(u)+ρω²u=0` y σxz/σzz en **ambas** caras. Además se evalúa Navier mediante diferencias finitas de cuarto orden directamente sobre ux/uz muestreados en 257 profundidades, sin usar las derivadas analíticas del helper.

En 12 combinaciones fijadas antes de comparar FDTD —E=6/12/24 kPa, ν=.45/.495, h=.6/1.2 mm, ρ=1000 kg/m³, f=1000 Hz— todas las verificaciones pasaron. Máximos relativos: Navier analítico 1.78×10⁻¹³; tracción 2.96×10⁻¹⁴; Navier por diferencias de cuarto orden 1.12×10⁻⁶. Las escalas de normalización son ρω² max|u| para Navier y μk max|u| para tracciones. Estos residuos prueban consistencia del eigenmodo, no precisión del FDTD.

`analytic_a0_checks.csv` y `.json` guardan cada condición, velocidad, kh, residuo secular, paridad y tracción superior/inferior. Ejecutar el script reproduce las verificaciones.

## Interpretación junto con FDTD

Una fuerza superficial localizada puede excitar A0, S0, modos superiores y campos cercanos. Un fasor FDTD en una ventana que todavía cambia entre periodos tampoco equivale a un eigenmodo estacionario. Comparar el eigenmodo con la parte FDTD suficientemente alejada de la fuente, de bordes absorbentes y de transitorios; reportar diferencias de espesor/geometría efectiva debidas a la grilla, cobertura y criterio de estacionariedad. No seleccionar únicamente los píxeles que se parecen al eigenmodo.

En una inclusión heterogénea, mostrar Young material y velocidad material/esperada con esas etiquetas. Una onda difractada/interferente no tiene necesariamente un único gradiente de fase local igual al coeficiente material. No etiquetar este eigenmodo homogéneo como solución exacta de la inclusión.
