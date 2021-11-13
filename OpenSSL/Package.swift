// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
		name: "OpenSSLSwift",
		pkgConfig: "openssl",
		providers: [
			.brew(["openssl"]),
		],
		products: [
			.library(name: "OpenSSLSwift", targets: ["OpenSSLSwift"]),
		],
		targets: [
			//.systemLibrary(name: "openssl", pkgConfig: "openssl", providers: [.brew(["openssl"])]),
			.target(name: "OpenSSLSwift", dependencies: ["openssl"])
		]
)
