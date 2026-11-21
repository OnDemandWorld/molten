# M1 Spike — MLXEmbedders on Mac and iPhone

PRD §10 M1 exit criteria: cosine > 0.999 between Mac and iPhone vectors on
100 sample texts; download size and memory recorded here.

## Configuration (K-E1)

| Item | Value |
|------|-------|
| Profile | `e5s-v1` |
| Model | `intfloat/multilingual-e5-small` |
| Pinned revision (HF commit) | `614241f622f53c4eeff9890bdc4f31cfecc418b3` |
| Dimensions | 384 |
| Pooling | mean |
| Normalization | L2 (unit length) |
| Prefixes | `"query: "` / `"passage: "` |
| Max input | 512 tokens |
| Packages | `mlx-swift`, `mlx-swift-lm` (MLXEmbedders, MLXLMCommon), `swift-huggingface`, `swift-transformers`, `MLXHuggingFace` (PRD §0.4 allowlist) |

## Method

1. Add the allowlisted packages to the Xcode project (SPM), products
   MLXEmbedders + MLXLMCommon linked to the app target.
2. Load `multilingual-e5-small` via `EmbedderRegistry` at the pinned revision
   through the MLX Hugging Face downloader; store under
   `Application Support/Molten/Models/` (K-E3).
3. Embed the same 100 sample texts (mixed English/Chinese, short and long,
   including code and tabular text) on Mac and on iPhone (device if
   available; otherwise iOS Simulator with the deviation recorded).
4. Export vectors (Float16, .mkv layout per §7.3) and compute pairwise
   cosine similarity Mac↔iPhone for each text.
5. Record: min/mean cosine, download size (bytes on disk), peak memory
   during embed, embed throughput (texts/s), cold-load time.

## Results (fill during spike)

| Metric | Mac | iPhone |
|--------|-----|--------|
| Min cosine (100 texts) | — | — |
| Mean cosine | — | — |
| Model download size | — | — |
| Peak memory during embed | — | — |
| Throughput (texts/s) | — | — |
| Cold-load time | — | — |

**Pass criterion:** min cosine > 0.999 (K-E5).

## Notes / deviations

- (record device vs simulator, MLX version pins, any API surprises)
