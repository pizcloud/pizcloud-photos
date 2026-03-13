# Infrastructure Layer

This folder contains the infrastructure layer for Pizcloud. It handles implementation-level concerns such as data sources, API clients, persistence adapters, and other external integrations.

## Structure

- **[Entities](./entities/)**: Classes that map domain models to storage schemas.
- **[Repositories](./repositories/)**: Concrete implementations of domain repository contracts. One contract can have multiple implementations.
- **[Utils](./utils/)**: Utility helpers dedicated to infrastructure concerns.

```
infrastructure/
├── entities/
│   └── user.entity.dart
├── repositories/
│   └── user.repository.dart
└── utils/
    └── database_utils.dart
```

## Usage

The infrastructure layer provides concrete classes for repository interfaces declared in the domain layer. Those implementations are exposed via Riverpod providers in the root `providers` directory.

```dart
// In domain/services/user.service.dart
final userRepository = ref.watch(userRepositoryProvider);
final user = await userRepository.getUser(userId);
```

The domain layer should avoid instantiating repository implementations directly and instead receive them through dependency injection.
