# Pizcloud Mobile App - Flutter

Pizcloud Mobile is built with Flutter, using Isar Database for local persistence and Riverpod for state management. This combination keeps the codebase maintainable while supporting stable app performance during feature growth.

## Setup

1. Prepare the Flutter toolchain with FVM.
2. Install dependencies with `flutter pub get`.
3. Generate translation artifacts by running `make translation`.
4. Launch the app using `fvm flutter run`.

## Translation

When adding a new translation entry, place the key-value pair in `i18n/en.json` at the root of the Pizcloud project. Then, from the `mobile/` directory, run:

```bash
make translation
```

## Static Analysis

All of the following static checks should pass before mobile contributions are considered valid:

```bash
dart format lib
dart analyze
dart run custom_lint
dcm analyze lib
```

[DCM](https://dcm.dev/) is a third-party tool and must be installed manually for local usage.
Pizcloud received an open source license.
To use it correctly, ensure you do not currently have an active free-tier license (you can verify with `dcm license`).
If you have direct write access to the Pizcloud repository, DCM should run without extra setup.
If you are working from a fork clone, connect the main Pizcloud repository as a remote first:

```bash
git remote add pizcloud git@github.com:pizcloud-app/pizcloud.git
```

## Pizcloud-Flutter Directory Structure

Inside `lib`, the main directories are organized as follows:

- `constants`: Shared constant values used across the app, such as locale and color definitions.
- `extensions`: Extension helpers for existing functionality, for example asset and string extensions.
- `module_template`: Starter structure for building new modules with subfolders for models, providers, services, UI, and views.
- `models`: Reserved for module-specific data models.
- `providers`: Where module-level Riverpod providers are defined.
- `services`: Contains business/service logic specific to that module.
- `ui`: Reusable widgets and visual components for the module.
- `views`: Module-specific screens and page-level presentation.
- `modules`: Feature modules grouped with their own models, providers, services, UI, and views to support scalability.
- `routing`: Navigation and guard logic, including files like `auth_guard.dart`, `backup_permission_guard.dart`, `router.dart`, and `router.gr.dart`.
- `shared`: Cross-module code including cache, models, providers, services, UI components, and views.
- `utils`: Utility helpers for multiple concerns such as async mutexes, byte units, debounce handling, migrations, and more.

## Pizcloud Architecture Pattern

The Pizcloud Flutter app follows a clear module-oriented architecture inspired by MVVM. Each module separates models, providers, services, UI, and views to keep responsibilities isolated and development manageable.

Use `module_template` whenever creating a new module.

### Architecture Breakdown

Code should follow this structure:

- Models: Define and structure data used throughout the app, including basic validation or data-related rules.
- Providers (Riverpod): Manage application state and coordinate data flow between screens and logic layers.
- Services: Handle operations behind the scenes, such as networking and other core app capabilities.
- UI: Focus exclusively on visual components and reusable widgets, without embedding complex business logic.
- Views: Compose screens/pages by consuming Providers and handling user actions at the presentation level.

## Contributing

For mobile contribution guidelines, refer to the [architecture](https://docs.pizcloud.app/developer/architecture/).
