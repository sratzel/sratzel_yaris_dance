Config = {}

Config.Debug = false

Config.Model = 'yaris99'
Config.DisplayName = 'Toyota Yaris'   -- gxt2 from the sp pack doesn't work in fivem

-- or https://cfx-nui-sratzel_yarisdance/audio/whys_this_dealer.mp3 / cdn
Config.AudioUrl = 'nui://sratzel_yarisdance/audio/whys_this_dealer.mp3'
Config.TrackMatch = { 'whys_this_dealer', 'why\'s this dealer' }

Config.VehicleSource = {
    enabled = true,
    command = 'dealer',
    toggleKey = 'F7',
    cooldown = 5000,
    range = 30.0,
    volume = 0.5
}

Config.ScanInterval = 500
Config.MaxDancers = 20
Config.ResyncThresholdMs = 80
Config.AudioLatencyMs = 0       -- tweak if squash is off the kick
Config.PhaseOffset = 0.0        -- beats

Config.WidthShare = 0.5
Config.BarAccent = 1.3
Config.BeatsPerCycle = 1
Config.IntroIdle = true
Config.PerCarJitter = 0.0       -- beats
Config.FadeMs = 150

-- 'auto' = alpha, invisible when damaged. 'alpha' | 'invisible'
Config.HideOriginal = 'auto'
Config.CopyWheels = true
-- 1.0 = one frame. occupants stick out the back: lower, front: higher. 0 = off
Config.MotionPrediction = 1.0

Config.ShowOccupants = true
Config.ScaleOccupants = true
-- 'seat' = clone sits in the proxy, 'pose' = fixed anim from OccupantAnims
Config.OccupantMode = 'seat'

-- only for 'pose', -1 = driver
Config.OccupantAnims = {
    [-1] = { 'veh@std@ds@base', 'sit' },
    [0]  = { 'veh@std@ps@base', 'sit' },
    [1]  = { 'veh@std@rds@base', 'sit' },
    [2]  = { 'veh@std@rps@base', 'sit' },
}

Config.Curve = {
    { 0.00, 1.00 },
    { 0.10, 0.75 },
    { 0.45, 1.28 },
    { 0.75, 0.97 },
    { 1.00, 1.00 }
}

Config.Texts = {
    title = 'Yaris',
    notYaris = 'Das geht nur im Yaris.',
    notDriver = 'Nur der Fahrer kann die Musik steuern.',
    cooldown = 'Nicht so schnell.',
    started = 'Why\'s this dealer?',
    stopped = 'Musik aus.',
    keyLabel = 'Yaris-Musik an/aus',
}
