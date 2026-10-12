# sratzel_yarisdance

every `yaris99` near a source playing "Why's this dealer" dances to the beat (squash & stretch).
the song can come from a yaris itself (`/dealer`) or from a boombox script.

> [!WARNING]
> no boombox included. there's only a hook for your own boombox script, see [boombox integration](#boombox-integration).

![yaris dance](../media/yaris_dance_fivem.gif)

standalone, no framework needed.

## requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- [xsound](https://github.com/Xogy/xsound)
- the `yaris99` vehicle (see `../yaris99`)
- the song as mp3 (see below)

## install

1. put `sratzel_yarisdance` and `yaris99` in your resources folder
2. add the song (see below)
3. server.cfg:

```
ensure ox_lib
ensure xsound
ensure yaris99
ensure sratzel_yarisdance
```

## song

the song is **not included**, you need to get it yourself.
reference: https://www.youtube.com/watch?v=ZIMX1MfM9i8

put it here:

```
sratzel_yarisdance/audio/whys_this_dealer.mp3
```

the beatmap in `shared/beatmap.lua` is timed to that exact version (135 bpm, first beat at 14.227 s, 129.6 s long).
if your file is cut differently, the cars will be off beat. fix it with `firstBeat` / `duration` in the beatmap
or `Config.AudioLatencyMs` / `Config.PhaseOffset`.

if xsound can't load the file over `nui://`, try the `https://cfx-nui-...` url from the config or host it somewhere.

## usage

| what | how |
|---|---|
| toggle music in your yaris | `/dealer` or `F7` (driver only, rebindable in settings) |
| debug info (F8) | `/yarisdebug` |

everyone in range hears the music and sees every yaris in range dance. after the song ends the source is removed.

## how it works

- **server** keeps all active sources in `GlobalState.yarisDance`. clients only read it.
- **time sync**: clients ping the server to get the offset to the server timer, so everybody computes the same song time.
  audio gets set to that time on start (late join works) and resynced if it drifts more than ~1 s.
- **dancing**: the real car isn't touched (physics, collision and sync stay normal). each client spawns a local,
  non-networked proxy car, hides the original and writes a scaled matrix onto the proxy every frame.
  volume stays the same and the wheels stay on the ground.
- **occupants**: seated peds can't be scaled, so they get a local clone too that sits in the proxy.
- the beatmap has rests (breaks in the song), the cars fade out there.

## config

all in `config.lua`. the interesting ones:

| option | default | what |
|---|---|---|
| `Model` | `'yaris99'` | vehicle model that dances |
| `AudioUrl` | `nui://...` | where xsound loads the song from |
| `TrackMatch` | | strings for `IsDanceTrack` (boombox) |
| `VehicleSource.command` / `toggleKey` | `dealer` / `F7` | |
| `VehicleSource.range` | `30.0` | hearing + dance range in m |
| `VehicleSource.volume` | `0.5` | |
| `VehicleSource.cooldown` | `5000` | ms between toggles |
| `MaxDancers` | `20` | max dancing cars per client, nearest first |
| `ScanInterval` | `500` | ms |
| `AudioLatencyMs` | `0` | shift dance vs audio |
| `PhaseOffset` | `0.0` | same in beats |
| `Curve` | | keyframes `{ phase, scale }` for one beat |
| `WidthShare` | `0.5` | how much of the squash goes into width vs length |
| `BarAccent` | `1.3` | stronger bounce on the first beat of each bar |
| `BeatsPerCycle` | `1` | 2 = half speed |
| `IntroIdle` | `true` | slight breathing during the intro |
| `PerCarJitter` | `0.0` | random offset per car in beats, so they're not 100 % in sync |
| `FadeMs` | `150` | fade in/out at rests and when leaving range |
| `HideOriginal` | `'auto'` | `'alpha'` keeps skidmarks, `'invisible'` doesn't. `'auto'` = alpha, invisible when damaged |
| `CopyWheels` | `true` | wheel spin + steering on the proxy |
| `MotionPrediction` | `1.0` | proxy lags one frame while driving. occupants stick out the back: lower, front: higher |
| `ShowOccupants` | `true` | false = hide occupants while dancing |
| `ScaleOccupants` | `true` | occupants squash with the car |
| `OccupantMode` | `'seat'` | `'pose'` as fallback (fixed anim from `OccupantAnims`) |
| `Texts` | | notifications |

## boombox integration

> [!WARNING]
> the boombox is not part of this script. you need your own (xsound based) and hook it up with these exports.

server side exports, if you want a boombox script to make the cars dance too.
the boombox plays its own audio, this script only does the dancing.

```lua
-- when the boombox starts a track
if exports.sratzel_yarisdance:IsDanceTrack(url) then
    exports.sratzel_yarisdance:AddSource('boombox:' .. id, {
        coords = coords,          -- vector3
        range = 25.0,
        soundName = soundName,    -- the xsound name the boombox uses
        startedAt = GetGameTimer(), -- server timer when the track was at 0:00
        loop = false,
    })
end

-- on stop / track change / pickup
exports.sratzel_yarisdance:RemoveSource('boombox:' .. id)
```

- seek or late start: calculate `startedAt` back, so it's the time the track would have been at 0:00
- boombox moved: call `AddSource` again with the same id (overwrites), max once a second

## license

the code is MIT, see `LICENSE`. the song and the vehicle are not covered by it.
