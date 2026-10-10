import 'package:campaign_sms/data/phone.dart';
import 'package:campaign_sms/data/segments.dart';
import 'package:campaign_sms/ui/new_message_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizePhone', () {
    test('accepts every form the source sheets use', () {
      const expected = '+251912345678';
      for (final input in [
        '0912345678',
        '+251912345678',
        '251912345678',
        '00251912345678',
        '0912 345 678',
        '(09) 12-345-678',
        '+251-912-345-678',
      ]) {
        expect(normalizePhone(input), expected, reason: input);
      }
    });

    test('accepts the 7-prefix range', () {
      expect(normalizePhone('0712345678'), '+251712345678');
    });

    test('rejects what is not an Ethiopian mobile', () {
      for (final input in [
        null,
        '',
        'not a number',
        '091234567', // 8 digits
        '09123456789', // 10 digits
        '0812345678', // 8 is not a mobile prefix
        '+14155550123',
      ]) {
        expect(normalizePhone(input), isNull, reason: '$input');
      }
    });

    test('gives a usable reason for rejects', () {
      expect(rejectionReason('091234567'), contains('9 digits'));
      expect(rejectionReason('0812345678'), contains('9 or 7'));
      expect(rejectionReason(''), contains('No phone'));
    });

    test('local form round-trips', () {
      expect(localForm('+251912345678'), '0912345678');
    });
  });

  group('countSegments', () {
    test('GSM-7 uses 160 then 153', () {
      expect(countSegments('a' * 160).segments, 1);
      expect(countSegments('a' * 160).encoding, SmsEncoding.gsm7);
      expect(countSegments('a' * 161).segments, 2);
      expect(countSegments('a' * 306).segments, 2);
      expect(countSegments('a' * 307).segments, 3);
    });

    test('GSM-7 extension characters cost two septets', () {
      // 80 euro signs = 160 septets = still one segment.
      expect(countSegments('€' * 80).segments, 1);
      expect(countSegments('€' * 81).segments, 2);
    });

    test('Amharic forces UCS-2 at 70 then 67', () {
      final info = countSegments('ሰላም' * 10); // 30 characters
      expect(info.encoding, SmsEncoding.ucs2);
      expect(info.unitsPerSegment, 70);
      expect(info.segments, 1);
      expect(countSegments('ሰ' * 71).segments, 2);
      expect(countSegments('ሰ' * 134).segments, 2);
      expect(countSegments('ሰ' * 135).segments, 3);
    });

    test('a single Amharic character taints an otherwise Latin message', () {
      final info = countSegments('${'a' * 100}ሰ');
      expect(info.isUnicode, isTrue);
      expect(info.nonGsmSample, 'ሰ');
      expect(info.segments, 2); // 101 UTF-16 units at 67 per segment
    });

    test('empty body still counts as one segment', () {
      expect(countSegments('').segments, 1);
    });
  });

  group('renderTemplate', () {
    test('substitutes the name', () {
      expect(
        renderTemplate('Hello {name}, welcome', 'Abebe', 'there'),
        'Hello Abebe, welcome',
      );
    });

    test('falls back for nameless and blank contacts', () {
      expect(renderTemplate('Hello {name}', null, 'there'), 'Hello there');
      expect(renderTemplate('Hello {name}', '   ', 'there'), 'Hello there');
    });

    test('does not leave a stranded comma when the fallback is blank', () {
      expect(
        renderTemplate('Hello {name}, welcome', null, ''),
        'Hello, welcome',
      );
    });

    test('leaves a template with no placeholder alone', () {
      expect(renderTemplate('Flat message', 'Abebe', 'there'), 'Flat message');
    });
  });

  group('the phone book, made fit to pick from', () {
    test('the same number saved twice is one person', () {
      // Android hands over a row per number, formatted however it was typed.
      // These four rows are two numbers.
      final tidy = tidyPhoneBook([
        (name: 'Abebe', phone: '+251 91 167 1220'),
        (name: 'Abebe', phone: '+251911671220'),
        (name: 'Abebe', phone: '0911671220'),
        (name: 'Sara', phone: '0911111111'),
      ]);
      expect(tidy.length, 2);
      expect(tidy.map((c) => c.name), ['Abebe', 'Sara']);
    });

    test('what cannot be texted is not offered', () {
      final tidy = tidyPhoneBook([
        (name: '*889#2', phone: '*889#2'),
        (name: 'Balance', phone: '*804#'),
        (name: 'Short', phone: '123'),
        (name: null, phone: ''),
        (name: 'Real', phone: '0911222333'),
      ]);
      expect(tidy.single.name, 'Real');
    });

    test('people come before bare numbers', () {
      // A phone book sorted by raw display name puts everything beginning
      // with a symbol first, which was the whole of the first screenful.
      final tidy = tidyPhoneBook([
        (name: null, phone: '0911000001'),
        (name: 'Zebib', phone: '0911000002'),
        (name: '0911000003', phone: '0911000003'),
        (name: 'Abebe', phone: '0911000004'),
      ]);
      expect(
        tidy.map((c) => c.name).toList(),
        ['Abebe', 'Zebib', null, null],
        reason: 'named first and alphabetical, unnamed after',
      );
    });

    test('a name that is only the number again is dropped', () {
      final tidy = tidyPhoneBook([
        (name: '+251 70 777 1690', phone: '+251707771690'),
      ]);
      expect(tidy.single.name, isNull);
      expect(tidy.single.phone, '+251707771690');
    });
  });
}
