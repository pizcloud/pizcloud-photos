# Domain Layer

This folder contains the domain layer for Pizcloud. It owns the core business rules of the application, including repository contracts, models, services, and shared utilities. Code in this layer should stay independent from presentation and infrastructure implementation details.

## Structure

- **[Interfaces](./interfaces/)**: Contracts that describe how data operations are accessed.
- **[Models](./models/)**: Core business data structures used by the app.
- **[Services](./services/)**: Business use-cases that coordinate with repositories.
- **[Utils](./utils/)**: Helper functions and utilities shared inside the domain layer.

```
domain/
├── interfaces/
│   └── user.interface.dart
├── models/
│   └── user.model.dart
├── services/
│   └── user.service.dart
└── utils/
    └── date_utils.dart
```

## Usage

The domain layer exposes business services that consume repositories through dependency injection. These services are made available by Riverpod providers under the root `providers` directory.

```dart
// In presentation layer
final userService = ref.watch(userServiceProvider);
final user = await userService.getUser(userId);
```

The presentation layer should not call repositories directly. It should go through domain services.
