with import <nixpkgs> {};
let
	impl = callPackage ./slinger-js/nix {};
in
mkShell {
	packages = [
		cairo.dev
		darwin.apple_sdk.frameworks.CoreFoundation
		darwin.apple_sdk.frameworks.Carbon
		darwin.apple_sdk.frameworks.Cocoa
		darwin.apple_sdk.frameworks.AppKit
		darwin.apple_sdk.frameworks.JavaScriptCore
		darwin.apple_sdk.frameworks.SwiftUI
		swift
		swiftpm
	];
	JS_BUNDLE_DIR = "${impl}/share/bundle";
}
