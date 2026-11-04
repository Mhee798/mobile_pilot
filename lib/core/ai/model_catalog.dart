import 'package:flutter_edge_ai/flutter_edge_ai.dart';

class DownloadableModel {
  const DownloadableModel(
    this.name,
    this.url,
    this.estimatedBytes,
    this.type,
    this.vision,
  );
  final String name, url;
  final int estimatedBytes;
  final ModelType type;
  final bool vision;
}

const downloadableModels = [
  DownloadableModel(
    'Gemma 4 E2B',
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    2600000000,
    ModelType.gemma4,
    true,
  ),
  DownloadableModel(
    'Gemma 4 E4B',
    'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
    3700000000,
    ModelType.gemma4,
    true,
  ),
];

const defaultCloudModel = 'gemini-3.5-flash-lite';

const cloudModels = {
  defaultCloudModel: 'Gemini 3.5 Flash-Lite',
  'gemini-3.8-flash': 'Gemini 3.8 Flash',
};

const modelFamilyLabels = {
  ModelType.general: 'General',
  ModelType.gemmaIt: 'Gemma / Gemma 3n',
  ModelType.gemma4: 'Gemma 4',
  ModelType.deepSeek: 'DeepSeek',
  ModelType.qwen: 'Qwen (ChatML)',
  ModelType.qwen3: 'Qwen 3',
  ModelType.qwen35: 'Qwen 3.5+',
  ModelType.llama: 'Llama',
  ModelType.hammer: 'Hammer',
  ModelType.functionGemma: 'FunctionGemma',
  ModelType.phi: 'Phi',
};
