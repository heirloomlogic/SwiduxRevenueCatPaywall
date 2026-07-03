# Contributing

## Enable dev tooling before your first build

This package gates its dev-only tooling — the [Persnoop](https://github.com/HeirloomLogic/Persnicket) `swift-format` linter and `swift-docc-plugin` — behind a gitignored `.dev-tooling` sentinel file, so that downstream consumers don't inherit them in their dependency graph.

Without the sentinel, `swift build` resolves a clean, consumer-mode manifest: no linting on build, no DocC. You'd then push a PR that fails the lint job in CI. To avoid that, create the sentinel once, **before your first build**:

```sh
touch .dev-tooling
```

That enables lint-on-build (in Xcode and the command line) and lets `swift package generate-documentation` resolve the DocC plugin — identical to how CI runs.

## If you already built without the sentinel

SwiftPM caches the evaluated manifest keyed on `Package.swift`'s *text*. The `.dev-tooling` file is external to that text, so creating it after a build won't take effect until you clear that one cache layer:

```sh
touch .dev-tooling
swift package purge-cache
swift package resolve
```

Note: `swift package reset` and Xcode's **Reset Package Caches** do **not** clear the evaluated-manifest cache — `purge-cache` is the specific verb. In Xcode, quit first, run `swift package purge-cache`, then reopen `Package.swift`.

The sentinel is gitignored and must never be committed — committing it would defeat the gate and ship the dev dependencies to everyone who clones a tag.

## About the committed Package.resolved

`Package.resolved` is committed so CI and contributors build against reviewed, pinned dependency revisions (Dependabot keeps it fresh). It is resolved *with* the sentinel present, so it also pins the dev tooling. Consumers never read a dependency's resolved file, so this costs them nothing — but if you build without the sentinel, SwiftPM will locally rewrite the file without the dev pins. Don't commit that diff; create the sentinel and re-resolve instead.
