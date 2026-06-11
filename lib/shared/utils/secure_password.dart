import 'dart:math';

/// Generates a cryptographically-strong temporary password.
///
/// Temp passwords are only ever used as the throwaway Firebase Auth credential
/// at account-provisioning time — the user immediately sets their own password
/// via the emailed reset/invite link, so this value should never be reused or
/// guessable. It is NOT stored anywhere.
///
/// The output is [length] chars (default 20) drawn from a 70+ symbol alphabet
/// using [Random.secure], and is guaranteed to contain at least one lowercase,
/// one uppercase, one digit and one symbol so it always satisfies Firebase's
/// password-strength minimum.
String generateSecurePassword([int length = 20]) {
  const lower   = 'abcdefghijkmnpqrstuvwxyz';
  const upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const digits  = '23456789';
  const symbols = '!@#\$%^&*()-_=+';
  const all     = lower + upper + digits + symbols;

  final rng = Random.secure();
  final chars = <String>[
    lower[rng.nextInt(lower.length)],
    upper[rng.nextInt(upper.length)],
    digits[rng.nextInt(digits.length)],
    symbols[rng.nextInt(symbols.length)],
    for (var i = 4; i < length; i++) all[rng.nextInt(all.length)],
  ];
  // Shuffle so the guaranteed chars aren't always in the first four positions.
  chars.shuffle(rng);
  return chars.join();
}
