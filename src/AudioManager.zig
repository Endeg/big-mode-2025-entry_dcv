const AudioManager = @This();

const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const c = @import("c.zig");

sounds: std.EnumArray(AudioAsset, c.Sound),

pub fn init() AudioManager {
    var sounds = std.EnumArray(AudioAsset, c.Sound).initUndefined();
    inline for (@typeInfo(AudioAsset).@"enum".fields) |audio_asset_field| {
        const audio_asset: AudioAsset = @enumFromInt(audio_asset_field.value);
        const wave_data = AudioAssets.get(audio_asset);

        const wave = c.LoadWaveFromMemory(".wav", wave_data.ptr, @intCast(wave_data.len));
        assert(c.IsWaveValid(wave));
        defer c.UnloadWave(wave);

        const sound = c.LoadSoundFromWave(wave);
        assert(c.IsSoundValid(sound));
        sounds.set(audio_asset, sound);
    }
    return .{ .sounds = sounds };
}

pub fn play(self: AudioManager, audio_asset: AudioAsset) void {
    c.PlaySound(self.sounds.get(audio_asset));
}

pub fn playOneOf(
    self: AudioManager,
    rng: std.Random,
    comptime audio_assets: []const AudioAsset,
) void {
    const sound_index = rng.uintLessThan(usize, audio_assets.len);
    self.play(audio_assets[sound_index]);
}

const AudioAssetsDir = "assets-to-embed/";

const AudioAsset = enum {
    PlayerStep,
    Pew,
    Damage0,
    Damage1,
    Damage2,
    Damage3,
    Damage4,
    DamageFromSupostat0,
    DamageFromSupostat1,
    DamageFromSupostat2,
    DamageFromSupostat3,
    EnemyFell0,
    EnemyFell1,
    EnemyFell2,
    PlayerFell,
    Respawn,
};

const AudioAssets = std.EnumArray(AudioAsset, []const u8).init(.{
    .PlayerStep = @embedFile(AudioAssetsDir ++ "Movement/Footsteps/sfx_movement_footsteps1b.wav"),
    .Pew = @embedFile(AudioAssetsDir ++ "Weapons/Lasers/sfx_wpn_laser10.wav"),
    .Damage0 = @embedFile(AudioAssetsDir ++ "General Sounds/Simple Damage Sounds/sfx_damage_hit1.wav"),
    .Damage1 = @embedFile(AudioAssetsDir ++ "General Sounds/Simple Damage Sounds/sfx_damage_hit2.wav"),
    .Damage2 = @embedFile(AudioAssetsDir ++ "General Sounds/Simple Damage Sounds/sfx_damage_hit3.wav"),
    .Damage3 = @embedFile(AudioAssetsDir ++ "General Sounds/Simple Damage Sounds/sfx_damage_hit4.wav"),
    .Damage4 = @embedFile(AudioAssetsDir ++ "General Sounds/Simple Damage Sounds/sfx_damage_hit5.wav"),
    .EnemyFell0 = @embedFile(AudioAssetsDir ++ "Death Screams/Alien/sfx_deathscream_alien3.wav"),
    .EnemyFell1 = @embedFile(AudioAssetsDir ++ "Death Screams/Alien/sfx_deathscream_alien4.wav"),
    .EnemyFell2 = @embedFile(AudioAssetsDir ++ "Death Screams/Human/sfx_deathscream_human5.wav"),
    .DamageFromSupostat0 = @embedFile(AudioAssetsDir ++ "Weapons/Melee/sfx_wpn_punch1.wav"),
    .DamageFromSupostat1 = @embedFile(AudioAssetsDir ++ "Weapons/Melee/sfx_wpn_punch2.wav"),
    .DamageFromSupostat2 = @embedFile(AudioAssetsDir ++ "Weapons/Melee/sfx_wpn_punch3.wav"),
    .DamageFromSupostat3 = @embedFile(AudioAssetsDir ++ "Weapons/Melee/sfx_wpn_punch4.wav"),
    .PlayerFell = @embedFile(AudioAssetsDir ++ "General Sounds/Negative Sounds/sfx_sounds_negative1.wav"),
    .Respawn = @embedFile(AudioAssetsDir ++ "General Sounds/Positive Sounds/sfx_sounds_powerup2.wav"),
});
