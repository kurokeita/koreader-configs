## Purpose

Defines what a userpatch in this repo must satisfy to actually take effect on the
KOReader release it claims to target: it must register under the plugin identity that
KOReader derives at runtime, it must declare that target explicitly, and its declared
verification level must reflect evidence rather than assumption.

## ADDED Requirements

### Requirement: Patches register under the runtime-derived plugin identity

Every patch that hooks a KOReader plugin SHALL register using the plugin name KOReader
derives at runtime for the pinned target. From KOReader 2026.07 onward that name is the
plugin's install directory name with the `.koplugin` suffix removed, and a plugin's
`_meta.lua` no longer overrides it.

A patch registered under a name no plugin resolves to produces no error, no log entry,
and no visible effect. Silent inactivity SHALL NOT be treated as success.

#### Scenario: Project: Title patch registers under the derived name

- **WHEN** a patch targets Project: Title, installed as `projecttitle.koplugin`
- **THEN** it registers under the plugin key `projecttitle`
- **AND** it does not register under the pre-2026.07 key `coverbrowser`

#### Scenario: Bookends patch is unaffected by the identity change

- **WHEN** a patch targets Bookends, installed as `bookends.koplugin`
- **THEN** it registers under the plugin key `bookends`, unchanged across the KOReader
  2026.03 to 2026.07 transition

#### Scenario: A patch that never fires is detected before release

- **WHEN** a patch registers under a plugin key that resolves to no installed plugin
- **THEN** the repo's verification SHALL report that patch as inactive
- **AND** the release SHALL NOT record it as compatible with the pinned target

### Requirement: Every patch declares its KOReader target explicitly

Every patch file SHALL carry an explicit, greppable KOReader version pin in a consistent
form, independent of whether the patch happens to hook a versioned plugin. A patch that
declares no pin SHALL be reported as unpinned, never as compatible with the current
target.

#### Scenario: Auditing patches against a target version

- **WHEN** the pinned patch set is audited against a given KOReader version
- **THEN** each patch resolves to exactly one of: compatible with the target, older than
  the target, or carrying no declared pin
- **AND** a patch with no declared pin is never reported as compatible

#### Scenario: A patch with no plugin dependency still declares a pin

- **WHEN** a patch hooks only KOReader core rather than a plugin
- **THEN** it still declares a KOReader version pin in the same form as plugin patches

### Requirement: Declared compatibility is backed by evidence at a stated level

A patch SHALL record the level at which its compatibility with the pinned target was
established, distinguishing a symbol-level check from a check of the hooked code's
behavior. A patch whose hooked upstream symbols changed in the target release SHALL NOT
be recorded as compatible on the strength of the registration fix alone.

#### Scenario: Hooked symbol is unchanged upstream

- **WHEN** every upstream symbol a patch hooks is present and unchanged in the pinned
  upstream release
- **THEN** the patch is recorded as verified at symbol level

#### Scenario: Hooked symbol changed upstream

- **WHEN** an upstream symbol a patch hooks was modified in the pinned upstream release
- **THEN** the patch SHALL be re-checked against the changed code before being recorded
  as compatible
- **AND** until that check is done it is recorded as unverified against the target

#### Scenario: Reference checkout too old to support the claim

- **WHEN** the local upstream reference checkout predates the pinned upstream release
- **THEN** compatibility claims against that release are recorded as unverified
- **AND** the reference is refreshed to the pinned release before verification proceeds

### Requirement: Version references across the repo agree with the manifest

The manifest SHALL be the single source of truth for the pinned KOReader release and
plugin tags. Every other version reference in the repo SHALL agree with it, with no
reference left pointing at a superseded target.

#### Scenario: Target is bumped

- **WHEN** the pinned KOReader release or a plugin tag changes in the manifest
- **THEN** the install documentation, the patch index, and each patch's own
  documentation state the same versions as the manifest
- **AND** no file still names the superseded version as the current target

#### Scenario: Point release notation differs upstream

- **WHEN** an upstream project refers to a KOReader point release in a notation that
  differs from KOReader's own release tag
- **THEN** the manifest records the version as KOReader tags it
- **AND** the upstream project's notation is noted where it could otherwise read as a
  mismatch
