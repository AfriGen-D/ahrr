# AHRR

A [Nextflow](https://www.nextflow.io/) workflow for human read removal. It
**wraps NCBI's [SRA Human Scrubber](https://github.com/ncbi/sra-human-scrubber)**
(v2.2.1) so it can be run behind a [GA4GH WES](https://github.com/ga4gh/workflow-execution-service-schemas)
endpoint. Reads are masked with `N` (default) or removed outright, and the
identified human reads can optionally be returned separately.

## This repository ships no database

AHRR contains the workflow, the container recipe and a service descriptor. It
does **not** include any k-mer database, and the container image does not
either. The scrubber needs a database to run; you supply your own, mounted
read-only at `params.db` (default `/opt/scrubber/data/human_filter.db`).

The database is deliberately never a per-job input: a submitter chooses among
what the node has, and cannot substitute or retrieve it. This lets the workflow
and image be public while a governed database stays on the node that holds it.

## Contents

| File | Purpose |
|---|---|
| `main.nf` | The `SCRUB` process: streams each input FASTQ through `scrub.sh` |
| `nextflow.config` | Resources and the `docker`, `singularity` and `k8s` profiles |
| `Dockerfile` | NCBI sra-human-scrubber pinned to a commit, run as a non-root user |
| `workflow.yaml` | Descriptor for a WES-backed service that offers this workflow |

## Quick start

```bash
docker build -t ahrr:2.2.1 .
nextflow run main.nf -profile docker \
    --reads sample.fastq.gz \
    --db /path/to/human_filter.db \
    --container ahrr:2.2.1
```

| Parameter | Default | Meaning |
|---|---|---|
| `--reads` | required | FASTQ path, or a list of paths; each file is scrubbed independently |
| `--db` | `/opt/scrubber/data/human_filter.db` | Database, read-only, node-local |
| `--remove` | `false` | `true` drops human reads; `false` masks them with `N` |
| `--keep_removed` | `false` | Also emit the removed human reads |
| `--cpus`, `--mem` | `2`, `4 GB` | Raise for large inputs and large databases |
| `--container` | `afrigend/sra-human-scrubber:2.2.1` | Image to run |

Each file is scrubbed independently and the scrubber has no knowledge of a
read's mate. For paired-end data use masking: removal would leave the two files
with different records.

## Running on Kubernetes

The `k8s` profile is site-specific. Set the claim names, mount paths and node
selector for your cluster with `--workClaim`, `--workMountPath`, `--dbClaim`,
`--dbMountPath` and `--nodeSelector` (or a params file). See the comments in
`nextflow.config`, in particular the note on the task UID and the ownership of
the database.

## Authors

Aaron Berkman, Mamana Mbiyavanga, Shaun Aron and Scott Hazelhurst.
See [`CITATION.cff`](CITATION.cff) for how to cite this workflow.

## Licence

[MIT](LICENSE). This applies to the workflow code in this repository only.
NCBI's SRA Human Scrubber is a separate work with its own terms, and any
database you use with it is governed by whatever terms apply to its source
data.
