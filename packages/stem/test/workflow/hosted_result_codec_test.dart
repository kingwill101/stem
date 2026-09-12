import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test(
    'hosted terminal results always pass through the nullable codec',
    () async {
      final codec = _NullableResultCodec();
      final workflow = HostedWorkflow<String, String?>(
        name: 'codec-result',
        resultCodec: codec,
        run: (_, input) => input == 'null' ? null : input,
      );
      final host = await WorkflowHost.inMemory(workflows: [workflow]);
      addTearDown(host.close);

      expect(await host.execute(workflow, 'null'), isNull);
      expect(await host.execute(workflow, 'value'), 'value');
      expect(codec.encoded, ['null', 'value']);
      expect(codec.decoded, ['sentinel', 'value']);
    },
  );
}

final class _NullableResultCodec extends Codec<String?, Object?> {
  final encoded = <String>[];
  final decoded = <String>[];

  @override
  Converter<String?, Object?> get encoder =>
      _Converter((value) {
        encoded.add(value ?? 'null');
        return value == null
            ? const {'sentinel': true}
            : <String, Object?>{'value': value};
      });

  @override
  Converter<Object?, String?> get decoder => _Converter((value) {
    if (value == null) {
      throw StateError('raw null was passed to the result codec');
    }
    if (value is Map && value['sentinel'] == true) {
      decoded.add('sentinel');
      return null;
    }
    if (value is Map && value['value'] is String) {
      decoded.add(value['value'] as String);
      return value['value'] as String;
    }
    throw FormatException('invalid result payload: $value');
  });
}

final class _Converter<S, T> extends Converter<S, T> {
  _Converter(this._convert);

  final T Function(S value) _convert;

  @override
  T convert(S input) => _convert(input);
}
