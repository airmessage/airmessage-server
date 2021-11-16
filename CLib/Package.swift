// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
		name: "CLib",
		products: [
			.library(name: "OpenSSL", targets: ["OpenSSL"]),
			.library(name: "Zlib", targets: ["Zlib"]),
		],
		targets: [
			.systemLibrary(name: "OpenSSL", pkgConfig: "openssl", providers: [.brew(["openssl"])]),
			.systemLibrary(name: "Zlib", pkgConfig: "zlib", providers: [.brew(["zlib"])]),
		]
)
