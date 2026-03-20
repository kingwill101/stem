# Stem Ecommerce Example

A small ecommerce API built with Shelf and Stem workflows.

This example demonstrates:

- mixed workflow styles:
  - annotated script workflow (`ecommerce.cart.add_item`) via `stem_builder`
  - manual flow workflow (`ecommerce.checkout`)
- SQLite persistence with Ormed models + migrations for store data
- Stem runtime on SQLite via `stem_sqlite` (also Ormed-backed)
- HTTP testing with `server_testing` + `server_testing_shelf`
- workflow steps reading/writing through a DB-backed repository

## Run

```bash
cd packages/stem/example/ecommerce
dart pub get
dart run build_runner build --delete-conflicting-outputs
dart run bin/server.dart
```

## Stem Builder Integration

The annotated workflow/task definitions live in:

- `lib/src/workflows/annotated_defs.dart`

`stem_builder` generates:

- `lib/src/workflows/annotated_defs.stem.g.dart`

From those annotations, this example uses generated APIs:

- `stemModule` (generated workflow/task bundle)
- `StemWorkflowDefinitions.addToCart`
- `StemWorkflowDefinitions.addToCart.startAndWait(...)`
- `StemTaskDefinitions.ecommerceAuditLog`
- direct task definition helpers like
  `StemTaskDefinitions.ecommerceAuditLog.enqueue(...)`

The manual checkout flow also derives a typed ref from its `Flow` definition:

- `checkoutWorkflowRef(checkoutFlow)`

The server wires generated and manual tasks together in one place:

```dart
final workflowApp = await StemWorkflowApp.fromUrl(
  'sqlite://$stemDatabasePath',
  adapters: const [StemSqliteAdapter()],
  module: stemModule,
  flows: [buildCheckoutFlow(repository)],
  tasks: [shipmentReserveTaskHandler],
);
```

That bootstrap path auto-subscribes the worker to the workflow queue plus the
default queues declared on the bundled module tasks and
`shipmentReserveTaskHandler`.
You only need an explicit `workerConfig.subscription` if you route work to
additional queues beyond those task defaults.

This is why the run command always includes:

```bash
dart run build_runner build --delete-conflicting-outputs
```

You can also use watch mode while iterating on annotated definitions:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

Database boot sequence on startup:

- loads [`ormed.yaml`](/run/media/kingwill101/disk2/code/code/dart_packages/stem/packages/stem/example/ecommerce/ormed.yaml)
- opens the configured SQLite file
- applies pending migrations from
  [`lib/src/database/migrations.dart`](/run/media/kingwill101/disk2/code/code/dart_packages/stem/packages/stem/example/ecommerce/lib/src/database/migrations.dart)
- seeds default catalog records if empty

Optional CLI migration command (when your local `ormed_cli` dependency set is compatible):

```bash
dart run ormed_cli:ormed migrate --config ormed.yaml
```

Server defaults:

- `PORT=8085`
- `ECOMMERCE_DB_PATH=.dart_tool/ecommerce/ecommerce.sqlite`

## API

- `GET /health`
- `GET /catalog`
- `POST /carts` body: `{ "customerId": "cust-1" }`
- `GET /carts/<cartId>`
- `POST /carts/<cartId>/items` body: `{ "sku": "sku_tee", "quantity": 2 }`
- `POST /checkout/<cartId>`
- `GET /orders/<orderId>`
- `GET /runs/<runId>`

## Test

```bash
cd packages/stem/example/ecommerce
dart test
```
