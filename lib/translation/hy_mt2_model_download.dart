import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../downloads/model_downloader.dart';

// Pinned source — the standard-quant GGUF from tencent/Hy-MT2-1.8B-GGUF.
// The smaller 1.25-bit/2-bit AngelSlim quantizations in sibling repos need a
// ggml kernel (STQ1_0) that isn't in mainline llama.cpp yet (still an open
// PR: https://github.com/ggml-org/llama.cpp/pull/22836), so no existing
// Flutter llama.cpp plugin can load them. Q4_K_M is a standard quant type
// any such plugin's vendored llama.cpp already understands. See
// docs/model-sources.md for the full record.
const _hyMt2BaseUrl =
    'https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF/resolve/main/';
const _hyMt2FileName = 'Hy-MT2-1.8B-Q4_K_M.gguf';
const _hyMt2Sha256 =
    'dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699';

// Hugging Face is unreliable from mainland China, so this also tries
// hf-mirror.com (a dedicated HF mirror) and ModelScope (Tencent's own
// official publish of this exact repository) as fallbacks. Both verified —
// matching size and, for ModelScope, the pinned SHA-256 directly via its
// API — to be the identical file, not a re-packaged copy.
const _hyMt2Urls = [
  '$_hyMt2BaseUrl$_hyMt2FileName',
  'https://hf-mirror.com/tencent/Hy-MT2-1.8B-GGUF/resolve/main/$_hyMt2FileName',
  'https://modelscope.cn/models/Tencent-Hunyuan/Hy-MT2-1.8B-GGUF/resolve/master/$_hyMt2FileName',
];

/// Computes the fixed destination path for the Hy-MT2 GGUF file, without
/// touching the filesystem.
Future<String> hyMt2ModelDestinationPath() async {
  final destinationDir = await getApplicationSupportDirectory();
  return '${destinationDir.path}/hy-mt2/$_hyMt2FileName';
}

/// Whether the Hy-MT2 GGUF file is already present at its fixed destination
/// path. Safe to trust without re-hashing — the only way a file lands there
/// is via [downloadAndVerify]'s atomic verify-then-rename.
Future<bool> isHyMt2ModelReady() async =>
    File(await hyMt2ModelDestinationPath()).exists();

/// Downloads and checksum-verifies the Hy-MT2 translation model to its fixed
/// destination path. Safe to call again after a failure or a kill mid-way —
/// [downloadAndVerify] re-checks whether the destination already verifies
/// before re-downloading.
///
/// [modelUrls]/[modelSha256] default to the real pinned sources (a primary
/// plus mirrors — see the fallback note above) and exist as parameters only
/// so tests can point this at a local fixture server.
Stream<DownloadProgress> downloadHyMt2Model({
  List<String> modelUrls = _hyMt2Urls,
  String modelSha256 = _hyMt2Sha256,
}) async* {
  yield* downloadAndVerify(
    DownloadSpec(
      urls: modelUrls,
      destinationPath: await hyMt2ModelDestinationPath(),
      sha256: modelSha256,
    ),
  );
}
