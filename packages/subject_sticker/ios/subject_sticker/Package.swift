// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "subject_sticker",
  platforms: [
    .iOS("13.0")
  ],
  products: [
    .library(name: "subject-sticker", targets: ["subject_sticker"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "subject_sticker",
      dependencies: []
    )
  ]
)
