# refmac_tools_jmh

A small collection of `tcsh` helper scripts that wrap CCP4's
[`refmac5`](https://www.ccp4.ac.uk/) for automated macromolecular
crystallographic refinement. The centerpiece is `converge_refmac.com`, which
runs `refmac5` over and over until the model stops moving, automatically
adjusting damping and weights and (optionally) building/pruning along the way.

Author: James Holton. Released under the [MIT License](LICENSE).

## Requirements

These are shell scripts, not a compiled package. You need:

- **`tcsh`** (the scripts use `#! /bin/tcsh -f`)
- **CCP4** on your `PATH`, providing `refmac5`, `mtzdump`, `mapdump`, `fft`,
  `mapmask`, and `cad`
- A handful of James Holton's companion scripts, bundled in this repo. Put the
  repo directory on your `PATH` so the drivers can find them:
  - `pick.com` — map peak picking (pruning)
  - `damp_pdb.com` — caps per-atom coordinate/B/occupancy shifts
  - `add_waters.com` — automated water building (`refmac_rigamrol.com`)
  - `rmsd` — coordinate RMSD between two PDBs
  - `FreeRer.com` — adds a free-R flag set to an MTZ if missing

## Scripts

### `converge_refmac.com`

The main driver. Repeatedly runs `refmac5` until the shifts fall below a
threshold (convergence), salvaging the best model seen.

```
converge_refmac.com model.pdb data.mtz [restraints.cif ...] [options]
```

Inputs are recognized by extension/type, so order does not matter:

- `*.pdb` — starting model (default `starthere.pdb`)
- `*.mtz` — data (default `./refme.mtz`)
- `*.cif` / `*.lib` — restraint/library files (may be repeated)
- an executable that prints `REFMAC` — used as the `refmac5` binary

Commonly used options (`key=value` unless noted):

| Option | Meaning |
| --- | --- |
| `trials=N` | maximum number of refmac runs (default 10000) |
| `NCYC=N` | refmac cycles per trial (default 5) |
| `runtime=SEC` | wall-clock limit; writes a stop file when exceeded |
| `diverge=N` | give up after N diverging trials (default 50) |
| `converge` / `noconverge` | enable/disable the convergence loop |
| `salvage` / `nosalvage` | keep/discard the best model on a bad exit |
| `append` | keep existing logs instead of clearing them |
| `weight_matrix=W` | refmac geometry weight (default 0.5) |
| `xray_weight=W` | explicit X-ray weight |
| `maxdXYZ=`, `maxdocc=`, `maxdB=` | per-atom shift caps (via `damp_pdb.com`) |
| `minB=`, `maxB=` | clamp B-factor range |
| `prune_lowocc[=x]` | delete atoms with occupancy below `x` (default 0.009) |
| `prune_highB[=x]` | delete atoms with B above `x` (default 499) |
| `prune_bad=N` | delete atoms sitting in strong negative difference density |
| `nudge_occ[=sigma]` | flag outlier-B atoms for occupancy refinement |
| `F000` | estimate the F000 term |
| `anomalous` / `noanomalous` | toggle anomalous refinement |

Shift thresholds can be given with a unit suffix: `0.01A` (coordinate),
`0.0O` (occupancy), `1B` (B-factor).

**Outputs** (in the working directory):

- `refmacout.pdb` / `refmacout.mtz` — latest refmac output
- `refmacout_minR.{pdb,mtz,log}` — best model by R-work
- `refmacout_minRfree.{pdb,mtz,log}` — best model by R-free
- `refmac_Rplot.txt` — per-trial stats: `n Rwork Rfree FOM LL LLfree rmsBond
  Zbond rmsAngle Zangle rmsChiral function vdw`
- `refmac_shifts.txt`, `refmac_scales.log` — shift and scale-factor history

**Control files** (read while running):

- `refmac_opts.txt` — extra refmac keywords passed through verbatim (`@`-style).
  Lines like `#LIBIN file.cif` add libraries.
- `refmac_stop.txt` — only active when `runtime=` is given: refmac is told to
  watch this file (`kill refmac_stop.txt`), and a background timer writes
  `stop Y` to it once the time limit is reached, triggering a clean exit that
  salvages the best model.
- `user_runme_script` — if present and executable, it is run each trial as
  `./user_runme_script <n>`; printing `converged` on its last line ends the loop.
- `evaluate.com` — optional, **user-defined**. If present and executable, it is
  run each trial as `./evaluate.com <model.pdb>`; a non-zero exit status signals
  convergence (stop), while a zero status means keep refining.

### `refmac_occupancy_setup.com`

Generates refmac `occupancy refine` / `occupancy group` keywords for a model
and writes them to `refmac_opts_occ.txt`.

```
refmac_occupancy_setup.com model.pdb [mode]
```

Modes:

- *(default)* — group alternate conformers per residue; waters and chain `S`
  become per-residue groups
- `allres` — one group per residue
- `allatoms` — one group per atom
- `allhet` — group all `HETATM` records
- `mcsc` — refine **m**ain-**c**hain and **s**ide-**c**hain alt-conf
  occupancies as *independent* "complete" groups (MC = backbone atoms plus the
  ALA Cβ; SC = everything else). Residues with fewer than two alts in a given
  role get no group for that role; waters/chain `S` are emitted as per-residue
  incomplete groups.

Typical use is to append the result into `refmac_opts.txt` so
`converge_refmac.com` picks it up.

### `refmac_rigamrol.com`

A higher-level protocol that alternates `converge_refmac.com` with automated
water building (`add_waters.com`), re-running occupancy setup each round and
gradually tightening the water-picking sigma/distance.

```
refmac_rigamrol.com [start.pdb] [refineme.mtz] [extra args passed through]
```

It adds a free-R set with `FreeRer.com` if the MTZ lacks one, and writes
`converge<round>.log` / `add_waters<round>.log` per round.

### `refmac_torsion_restraints.txt`

A ready-made set of refmac torsion-angle restraint keywords (backbone φ/ψ/ω
and side-chain χ rotamer preferences). Include it in your refmac keywords to
bias toward favorable rotamers.

## Quick start

```tcsh
# basic auto-convergence
converge_refmac.com model.pdb data.mtz restraints.cif trials=30

# set up alt-conf occupancy refinement first, then converge
refmac_occupancy_setup.com model.pdb mcsc >> refmac_opts.txt
converge_refmac.com model.pdb data.mtz
```
