# Záloha větví swamp a water z gen_sounds.step() před přepracováním (zvuky ve stejné složce).

    elif surface == "swamp":
        # Močál: čvachtnutí do bahna. Tlumený mokrý úder a za ním několik krátkých mokrých
        # mlasknutí (úzká pásma šumu s ostrým náběhem), jak se bláto rozstřikuje a noha zvedá.
        out += thump(rng, length, 220, 0.05) * 0.8
        out += band(noise(rng, length), 250, 1200) * envelope(length, 0.004, 0.035) * 0.55
        for _ in range(rng.integers(3, 6)):
            size = seconds(rng.uniform(0.02, 0.05))
            low = rng.uniform(250, 600)
            smack = band(noise(rng, size), low, low * rng.uniform(2.0, 3.0)) * envelope(size, 0.001, rng.uniform(0.006, 0.014))
            place(out, smack, rng.uniform(0.02, 0.16), rng.uniform(0.35, 0.8))
        # Mokré čvachtání: po dopadu pár set ms nepravidelně bublá a mlaská (šum s rychlou
        # nepravidelnou modulací) a praskají bublinky bahna (úzká pásma šumu, rychle doznějí).
        tail = seconds(0.16)
        wobble = np.clip(band(noise(rng, tail), 15, 60, 1) * 12.0 + 0.4, 0.0, 1.2)
        slosh = band(noise(rng, tail), 280, 1300) * wobble * envelope(tail, 0.02, 0.06)
        place(out, slosh, rng.uniform(0.03, 0.05), 0.6)
        for _ in range(rng.integers(4, 8)):
            size = seconds(rng.uniform(0.03, 0.06))
            f0 = rng.uniform(220, 650)
            pop = band(noise(rng, size), f0 * 0.88, f0 * 1.12) * envelope(size, 0.002, rng.uniform(0.01, 0.02))
            place(out, pop, rng.uniform(0.04, 0.2), rng.uniform(0.6, 1.2))
        # Mokrý lesk: krátké vysoké šplíchy rozstřiku a syčení vody v bahně, ať zvuk není
        # tlumený.
        out += band(noise(rng, length), 1800, 6000) * envelope(length, 0.002, 0.03) * 0.35
        for _ in range(rng.integers(4, 8)):
            size = seconds(rng.uniform(0.008, 0.02))
            low = rng.uniform(1500, 3000)
            spray = band(noise(rng, size), low, low * 2.2) * envelope(size, 0.0008, 0.005)
            place(out, spray, rng.uniform(0.0, 0.18), rng.uniform(0.25, 0.55))
        tail = seconds(0.16)
        fizz = band(noise(rng, tail), 2500, 7000) * np.clip(band(noise(rng, tail), 20, 80, 1) * 14.0, 0.0, 1.0)
        place(out, fizz * envelope(tail, 0.02, 0.05), 0.04, 0.25)
        out = lowpass(out, 7500, 2)
    elif surface == "water":
        # Brod: šplouchnutí (šum se střední barvou, rychlý náběh) a pár bublinek po něm.
        length = seconds(0.4)
        out = np.zeros(length)
        out += band(noise(rng, length), 500, 3200) * envelope(length, 0.006, 0.07) * 0.8
        out += band(noise(rng, length), 2500, 7000) * envelope(length, 0.002, 0.025) * 0.25
        out += thump(rng, length, 220, 0.04) * 0.5
        for _ in range(rng.integers(3, 7)):
            dur = rng.uniform(0.015, 0.04)
            size = seconds(dur)
            tt = np.arange(size) / RATE
            f0 = rng.uniform(500, 1400)
            chirp = np.sin(2 * math.pi * (f0 * tt + f0 * 2.5 * tt * tt / dur))
            place(out, chirp * envelope(size, 0.002, dur * 0.35), rng.uniform(0.04, 0.22), rng.uniform(0.08, 0.2))
