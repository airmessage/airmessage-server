// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OpenSSL",
    pkgConfig: "openssl",
    targets: [
		.systemLibrary(name: "openssl", pkgConfig: "openssl", providers: [.brew(["openssl"])]),
		.target(name: "OpenSSL", dependencies: ["openssl"])
    ]
)
