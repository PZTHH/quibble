// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuibbleInference",
    platforms: [.macOS(.v14)],
    products: [.library(name: "QuibbleInference", targets: ["QuibbleInference"])],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "bf14ae0c26e4e85553dd989571cae29d70fa6735"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.31.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.31.3"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", exact: "1.3.4"),
    ],
    targets: [
    .target(name: "QuibbleWhisper", dependencies: [
        .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
        .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXNN", package: "mlx-swift"),
        .product(name: "MLXFast", package: "mlx-swift"),
        .product(name: "Tokenizers", package: "swift-transformers"),
    ], exclude: ["LICENSE", "PROVENANCE.md"]),
    .target(name: "QuibbleInference", dependencies: ["QuibbleWhisper",
        .product(name: "QuibbleCore", package: "quibble"),
        .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
        .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "Tokenizers", package: "swift-transformers"),
        .product(name: "MLX", package: "mlx-swift"),
    ])]
)
