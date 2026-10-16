#!/usr/bin/env python3
"""Příšery z pohledu shora: had, pavouk, vlk, ptakoještěr, tyranosaurus a kamenná koule.

64 px je 1 m, stejně jako u postavy, skal a stromů. Kreslí se ve čtyřnásobném
rozlišení do plátna druhu (canvas). Uložená buňka vrstvy je ořezaná na obsah,
střed zůstává.

Atlas má osm sloupců, příšera jde na sever. Ostatní směry otáčí uzel v Godotu.
Počet snímků cyklu (frames) má každý druh v katalogu: pavouk a vlk 8, had a
tyranosaurus 16, ptakoještěr 24. Delší animace se zalomí do dalších řádků (atlas_columns).
Jeden atlas slouží všem materiálům druhu, barvy dodá shader.

Vrstva nese masky, ne hotovou barvu: R světlost, G podíl akcentu (kresba,
proužky), B oči, A krytí. Barva ve hře:
  tělo = barva materiálu * mix(0.35, 1.15, R)
  kůže = mix(tělo, akcent * mix(0.6, 1.1, R), G)
  výsledek = mix(kůže, oči, B)
Který materiál patří kterému druhu, určuje gen_crystal.MATERIALS (klíč monster).
Tělo má barvu color materiálu, akcent jeho monster_accent, jinak glint. Oči mají
barvu druhu.

Chodidlo na zemi jede vůči tělu rovnoměrně dozadu. Za cyklus příšera urazí
cycle_meters z katalogu a chodidla přitom neklouzají.

Had: vrstva 1 (tělo na zemi, 0 m), vrstva 2 (zvednutá hlava a krk, 0,35 m). Tělo
ve vrstvě 1 začíná už pod hlavou, aby se vrstvy při posunu kamery neroztrhly. Plazí se
vlněním do stran: vlna stojí vůči zemi a had po ní klouže, za cyklus urazí jednu vlnovou
délku. Hlava a krk se nevlní, jen natáčejí, výchylka roste k ocasu. Na hřbetě jsou
kosočtverce v akcentu s tmavým lemem, jazyk má barvu očí a vyjede dvakrát za cyklus.

Pavouk: vrstva 1 (nohy a makadla, 0 m), vrstva 2 (hlavohruď a zadeček, 0,5 m).
Kořeny nohou zajíždějí pod hlavohruď, aby se vrstvy při posunu kamery neroztrhly.
Chodí střídavě: L1 P2 L3 P4 spolu, druhá čtveřice o půl cyklu později.

Kamenný golem (pavouk2) chodí jako pavouk, ale celý je z kamenů ve stylu krystalů:
tmavý lem, zkosené plošky, plochý vrchol. Tělo jsou hromádky kamenů na tmavém jádru,
končetiny řady protažených kamenů, svítí jen oči. Kresba jako u pavouka (pruh na hrudi,
kříž a krokve na zadečku, proužky na noze) je vtlačená do kamenů. Semínka odlesků jsou
ve zvláštním atlasu layer_N_spark.png (G jako u krystalu, jas je fáze bliknutí), v katalogu
sparkle_file vrstvy. Hra ho kreslí shaderem monster_stone_layer ("shader": "stone"),
odlesky mají barvu glint a sílu sparkle materiálu. Náhled _trpyt.gif ukazuje blikání.

Vlk: vrstva 1 (nohy, 0 m), vrstva 2 (trup, ocas a hlava, 0,75 m). Klusá:
levá přední a pravá zadní spolu, druhý pár o půl cyklu později. Srst dělají
chomáče na obrysu, hřbet má tmavší sedlo (jen světlost R), maska, hříva a
špička ocasu jsou v akcentu.

Ptakoještěr pořád letí: vrstva 1 je jeho stín na zemi (0 m, jen krytí, v katalogu
shadow), vrstva 2 je tvor ve výšce letu (4 m). Při posunu kamery se stín od tvora
vzdálí. Stín hra kreslí černě s krytím shadow_alpha z katalogu. Cyklus je jedno
mávnutí: dolů jde křídlo roztažené, nahoru složené v zápěstí. Snímek glide_frame
se hodí na plachtění. Hřbet je tmavší a nohy jen vykukují zpod těla, aby tvor
nepůsobil jako zespodu. Konce křídel jsou v akcentu.

Tyranosaurus: vrstva 1 (nohy, 0 m), vrstva 2 (stehna, trup, ocas, ruce a hlava,
1,2 m). Holeň začíná pod stehnem, chodidlo vykukuje vedle břicha a kořene ocasu.
Kyčle se kývají k noze na zemi, ocas se vlní a hlava kývá proti kyčlím.

Kamenná koule (koule2) je jen z kamenů, valí se a nemá kamennou předlohu. Vrstva 1
(0 m) je celá koule tmavší, vrstva 2 (0,55 m) světlejší vršek s očima. U kraje obrazovky
spodní vrstva vykoukne jako bok koule. Kameny leží na povrchu koule a za cyklus se koule
jednou otočí dopředu, takže urazí svůj obvod a kameny po zemi neklouzají. U horizontu se
kameny zploští, vpředu zmizí a zezadu se vynoří. Rudé oči v tmavých důlcích se netočí, kameny
se valí pod nimi. Šikmé víčko a kamenné obočí je zamračí. Úplně vpředu je zamračená tlama
s kamennými zuby, uvnitř žhne. Za cyklus dvakrát kousne: spodní čelist pomalu klesne dopředu,
žár se rozsvítí a tlama rychle cvakne, zuby se zaklesnou do sebe. Oči a tlama jsou na pevné obličejové desce, která
se netočí, valící se kameny zajíždějí pod její okraj. Okraj desky na kouli je poloprůhledný
přechod, kameny pod ním postupně prosvítají. Deska je vysunutá dopředu a vpředu
trochu přečnívá přes obrys koule jako vystrčená čelist. Za obličejem vede přes vršek
hřbetní hřeben, nepravidelný pás kamenů, který se valí stejným směrem jako koule, ale
čtyřikrát pomaleji. Vede jen od obličeje kousek za střed koule a ke konci plynule zmizí.
Zvuky má vlastní (kamenné dunění v gen_sounds).

Atlasy jdou do godot/graphics/characters/monsters, náhledy do tools/preview.

  py tools/gen_monsters.py
  py tools/gen_monsters.py --name tyranosaurus
"""

from __future__ import annotations

import argparse
import bisect
import json
import math
from pathlib import Path
from typing import Callable

from PIL import Image, ImageChops, ImageDraw, ImageFilter

from gen_crystal import MATERIALS, parse_hex
from gen_trees import blank, contact_sheet, crop_square, on_grass, pack_atlas

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "godot" / "graphics" / "characters" / "monsters"
INFO_PATH = OUT_DIR / "monsters.json"
PREVIEW = ROOT / "tools" / "preview"

PX_PER_METER = 64
# Atlas má tolik sloupců, delší animace se zalomí do dalších řádků.
COLUMNS = 8
# Délka jednoho cyklu v náhledových GIFech, pokud ho druh nepřepíše.
PREVIEW_CYCLE_MS = 720
# Kolik snímků ukáže přehled _chuz.png. Delší animace ukáže jen každý n-tý.
SHEET_FRAMES = 8
SS = 4
# Stejné číslo jako ObjectLayers.PARALLAX. Náhled „u kraje“ je příšera 480 px vpravo a 260 px pod středem okna.
PARALLAX = 0.016
EDGE = (480.0 * PARALLAX, 260.0 * PARALLAX)
# Rozsah světlosti R pro barvu těla a pro barvu akcentu.
SHADE = (0.35, 1.15)
ACCENT_SHADE = (0.6, 1.1)
# Blikání odlesků jako v crystal.gdshader: rychlost v rad/s, perioda a kolik cyklů chůze
# ukáže náhled _trpyt.gif. Náhled trvá jednu periodu, aby se smyčka nezadrhla.
SPARKLE_SPEED = 2.4
SPARKLE_PERIOD = math.tau / SPARKLE_SPEED
SPARKLE_CYCLES = 4
# Krytí stínové vrstvy, kreslí se černě.
SHADOW_ALPHA = 0.35
# Počet soustředných pásů, ze kterých se skládá stínovaná trubice.
TUBE_BANDS = 16

Point = tuple[float, float]

# Pavouk. Souřadnice jsou v px od středu plátna, záporné Y je vpřed.
# Střed je zadní kraj hlavohrudi, kolem něj se pavouk ve hře otáčí.
SPIDER_CANVAS = 128
PROSOMA = (0.0, -1.0)
PROSOMA_R = (10.0, 11.5)
ABDOMEN = (0.0, 24.0)
ABDOMEN_R = (13.5, 16.5)
# Zadeček se kolem stopky kývá do stran, ve stupních.
PEDICEL = (0.0, 9.0)
SWAY = 4.0
# Kyčel, chodidlo v klidu a ohyb kolena pravé strany od předu. Levá strana je zrcadlo.
# Kladný ohyb posune koleno dozadu, přední nohy pak špičkou míří dopředu.
LEGS: tuple[tuple[Point, Point, float], ...] = (
    ((4.5, -8.0), (24.0, -40.0), 5.0),
    ((7.5, -4.0), (40.0, -17.0), 3.0),
    ((8.5, 1.0), (41.0, 12.0), -3.0),
    ((6.5, 5.5), (30.0, 40.0), -5.0),
)
# Stehno a holeň jako násobek klidové vzdálenosti kyčle od chodidla.
FEMUR = 0.68
TIBIA = 0.80
# Poloměr nohy u kyčle, v koleni a na špičce.
LEG_RADIUS = (2.5, 2.0, 1.3)
# Světlé kroužky na holeni, od kolena ke špičce jako díl délky.
LEG_BANDS = ((0.0, 0.12), (0.5, 0.62))
# Výšky v px. Kyčel je pod hlavohrudí. Světlost nohy roste s výškou až do TOP_Z.
HIP_Z = 9.0
TOP_Z = 26.0
# Chodidlo na zemi ujede vůči tělu STRIDE px dozadu. Cyklus jsou dva kroky.
STRIDE = 16.0
LIFT = 9.0
# Zvednuté chodidlo se přitáhne ke kyčli o tenhle díl vzdálenosti.
PULL = 0.15
# Kořen nohy je takový díl cesty od kyčle ke středu hlavohrudi.
TUCK = 0.6
# Makadlo pravé strany: kořen, kyčel, koleno, špička a jejich výšky.
PALP: tuple[Point, ...] = ((2.5, -6.0), (4.0, -10.5), (7.0, -14.5), (5.0, -19.5))
PALP_Z = (9.0, 9.0, 14.0, 5.0)
PALP_RADIUS = (1.8, 1.6, 1.9)
PALP_WIGGLE = 1.4
# Oči pravé strany: střed a poloměr. Přední pár je největší.
EYES = (
    ((1.8, -9.8), 1.4),
    ((5.0, -8.4), 1.0),
    ((2.4, -6.4), 0.8),
    ((5.7, -5.4), 0.9),
)
# Kříž a krokve na zadečku, v poloměrech zadečku. Poslední číslo je síla akcentu.
CROSS = (
    ((0.0, -0.56), 1.5, 1.0),
    ((0.0, -0.28), 2.1, 1.0),
    ((0.0, 0.02), 1.7, 1.0),
    ((0.0, 0.30), 1.3, 1.0),
    ((-0.36, -0.28), 1.5, 1.0),
    ((0.36, -0.28), 1.5, 1.0),
)
CHEVRONS = (0.50, 0.68, 0.84)

# Kamenný golem (pavouk2) má stejnou kostru a chůzi jako pavouk, ale celý je z kamenů.
# Kameny těla: střed v poloměrech části těla a poloměr v px. Kreslí se od kraje ke středu.
STONES: tuple[tuple[Point, float], ...] = (
    ((-0.42, -0.5), 7.0),
    ((0.45, -0.45), 7.4),
    ((-0.5, 0.32), 7.6),
    ((0.52, 0.28), 7.0),
    ((0.0, 0.8), 6.4),
    ((0.0, -0.05), 7.8),
)
PROSOMA_STONES: tuple[tuple[Point, float], ...] = (
    ((-0.55, 0.42), 5.2),
    ((0.55, 0.42), 5.0),
    ((-0.5, -0.4), 5.0),
    ((0.5, -0.42), 5.2),
    ((0.0, 0.05), 6.6),
)
# Kusadla: střed a poloměr kamene pravé strany.
FANG_STONE = ((2.7, -13.6), 3.2)
# Kameny článku končetiny: (od, do, poloměr), od a do jako díl článku, poloměr jako násobek
# tloušťky končetiny v místě. Kámen je protažený podél článku nejvýš o STONE_STRETCH.
# Čtvrté číslo je podíl akcentu: obarvené kameny dělají proužky jako na noze pavouka.
FEMUR_STONES = ((0.08, 0.5, 1.5, 0.0), (0.52, 0.94, 1.45, 0.0))
TIBIA_STONES = ((0.06, 0.4, 1.55, 0.0), (0.42, 0.74, 1.5, 0.85), (0.76, 1.0, 1.3, 0.0))
PALP_STONES = ((0.1, 0.9, 1.3, 0.0),)
STONE_STRETCH = 1.5
# Kloub v koleni, poloměr v px a podíl akcentu.
STONE_KNEE = 3.0
STONE_KNEE_ACCENT = 0.85
# Světlost zkosených plošek jako násobek, od nejtmavší po nejsvětlejší. Vrchol je o kus světlejší.
STONE_FACET = (0.28, 1.0)
# Vrchol kamene je obrys zmenšený tímhle poměrem ke středu.
STONE_TOP = 0.52
# Počet rohů kamene, nejméně a nejvíc.
STONE_SIDES = (5, 7)
# Tmavý lem kolem kamene v px.
STONE_RIM = 0.7
# Odlesky: takový díl kamenů těla a končetin má semínko třpytu. Semínko je v G jako u krystalu,
# jeho jas je fáze bliknutí. Poloměr semínka je v px výsledného obrázku.
SPARK_BODY = 0.7
SPARK_LEG = 0.25
SPARK_RADIUS = 1.35

# Vlk, asi 2 m od čenichu po špičku ocasu. Střed plátna je uprostřed trupu.
WOLF_CANVAS = 176
# Vlk se kreslí v rozměrech výše a do atlasu se zmenší tímhle poměrem.
WOLF_ZOOM = 0.85
# Trup od šíje po záď: Y a poloviční šířka v px. Nejširší je hříva na plecích.
WOLF_BODY = (
    (-32.0, 10.0),
    (-25.0, 14.0),
    (-17.0, 17.0),
    (-7.0, 16.0),
    (3.0, 14.0),
    (11.0, 12.5),
    (18.0, 13.5),
    (24.0, 12.0),
    (29.0, 8.0),
)
# Hlava od týla po čenich, klín. Nejširší jsou líce.
WOLF_HEAD = (
    (-29.0, 10.0),
    (-34.0, 12.5),
    (-40.0, 11.5),
    (-45.0, 9.0),
    (-50.0, 7.0),
    (-55.0, 5.4),
    (-60.0, 4.2),
    (-62.5, 3.0),
)
WOLF_NECK = -29.0
WOLF_TAIL = (
    (26.0, 6.0),
    (33.0, 8.5),
    (43.0, 10.0),
    (53.0, 9.5),
    (62.0, 6.5),
    (69.0, 2.8),
)
WOLF_TAIL_WAVE = 6.0
# Od tohoto dílu délky je ocas v barvě akcentu.
WOLF_TAIL_TIP = 0.72
# Plece a záď se v klusu kývají na opačné strany, v px. Hlava se natáčí ve stupních.
WOLF_FLEX = 1.2
WOLF_HEAD_YAW = 2.5
# Kloub a tlapa v klidu pravé strany, přední a zadní noha.
WOLF_LEGS: tuple[tuple[Point, Point], ...] = (
    ((9.0, -13.0), (16.0, -16.0)),
    ((9.0, 17.0), (15.0, 19.0)),
)
WOLF_STRIDE = 40.0
WOLF_PULL = 0.1
WOLF_TOES = (-36.0, -12.0, 12.0, 36.0)
# Sedlo tmavne ke hřbetu po pruzích: šířka pruhu jako díl šířky trupu a kolik světlosti trupu mu zůstane.
WOLF_SADDLE = ((0.78, 0.94), (0.68, 0.88), (0.58, 0.82), (0.48, 0.76), (0.38, 0.72))
WOLF_SADDLE_Y = (-20.0, 24.0)
WOLF_EYE = ((4.4, -44.5), 1.5)
# Světlý čenich a líce u okraje hlavy: od, do, poloměr a síla akcentu.
WOLF_MUZZLE = ((0.0, -47.0), (0.0, -56.5), 4.0, 0.55)
WOLF_CHEEK = ((9.2, -32.5), (8.8, -40.0), 2.0, 0.55)
# Ucho pravé strany: vnitřní a vnější kraj kořene, špička. Sedí v zadním rohu lebky a míří dozadu ven.
# Tmavý lem ho oddělí od hlavy i u světlých materiálů.
WOLF_EAR: tuple[Point, ...] = ((3.6, -35.5), (9.4, -38.5), (10.6, -29.0))

# Řady kamenů podél těla (stone_band, kamenný vlk a tyranosaurus). Užší místo než BAND_STONE_ACROSS[0] px
# má jeden kámen vedle sebe, užší než [1] dva, jinak tři, každá druhá řada o kámen míň.
# Kámen má poloměr BAND_STONE_SIZE šířky na jeden kámen, krajní sedí na BAND_STONE_SPREAD
# šířky od páteře podle počtu, rozestup řad je BAND_STONE_STEP poloměru.
BAND_STONE_ACROSS = (7.0, 13.5)
BAND_STONE_SIZE = 0.95
BAND_STONE_SPREAD = {2: 0.45, 3: 0.62}
BAND_STONE_STEP = 1.2
BAND_STONE_STRETCH = 1.1
# Kámen se posune o tolik dílu šířky do strany a dílu poloměru podél, ať řady nejsou rovné.
BAND_STONE_JITTER = 0.18
# Hřbet kamenného vlka (vlk2) v sedle má tolik světlosti, ke krajům se zesvětlí.
WOLF_STONE_SADDLE = 0.6
# Kameny nohy jako FEMUR_STONES: od, do, poloměr a akcent.
WOLF_LEG_STONES = ((0.05, 0.5, 1.05, 0.0), (0.5, 0.95, 1.0, 0.0))
# Kameny hlavy: střed (pravá strana, x 0 je na ose), poloměr a akcent. Od týla k čenichu.
WOLF_HEAD_STONES = (
    ((0.0, -28.0), 8.0, 0.0),
    ((0.0, -33.5), 7.5, 0.0),
    ((5.2, -38.5), 5.2, 0.0),
    ((8.6, -35.5), 3.2, 0.55),
    ((0.0, -42.5), 6.2, 0.0),
    ((0.0, -50.0), 4.6, 0.55),
    ((0.0, -56.5), 3.6, 0.55),
)

# Ptakoještěr, rozpětí asi 3,2 m. Střed plátna je mezi rameny a kyčlemi.
PTERO_CANVAS = 240
PTERO_HEIGHT = 4.0
# Za jedno mávnutí uletí tolik metrů. Mávání je pomalé a velké, proto víc snímků.
PTERO_CYCLE = 2.5
PTERO_FRAMES = 24
# Ve čtvrtině mávnutí jsou křídla vodorovně a roztažená, ten snímek se hodí na plachtění.
PTERO_GLIDE_FRAME = PTERO_FRAMES // 4
# Největší náklon křídla ve stupních a jak moc se křídlo při švihu nahoru složí.
PTERO_FLAP = 70.0
PTERO_FOLD = 0.75
# Rameno pravého křídla. Kosti (pažní, předloktí, prst): délka, úhel roztaženého a složeného křídla.
# Úhel 0 míří ven, kladný dozadu.
PTERO_SHOULDER = (7.0, -8.0)
PTERO_BONES = ((22.0, -8.0, 15.0), (20.0, -12.0, 35.0), (55.0, 24.0, 55.0))
# Náběžná hrana začíná na trupu před ramenem. Blána před předloktím vystupuje o PTERO_PROPATAGIUM px.
PTERO_ROOT: tuple[Point, ...] = ((1.0, -9.0), (6.0, -12.0))
PTERO_PROPATAGIUM = 4.0
# Odtoková hrana od trupu ke špičce: kořen na trupu a kotník, hloubka blány za loktem
# a zápěstím, pak díl délky prstu a hloubka blány za ním.
PTERO_TRAIL_ROOT: tuple[Point, ...] = ((1.0, 16.0), (6.5, 24.0))
PTERO_TRAIL_ELBOW = 24.0
PTERO_TRAIL_WRIST = 19.0
PTERO_TRAIL = ((0.15, 14.0), (0.45, 10.0), (0.75, 5.0))
PTERO_SAMPLES = 40
# Konec křídla v barvě akcentu: odkud podél rozpětí začíná, kolik kroků a váha u špičky.
PTERO_TIP = (0.6, 6, 0.85)
# Svaly pravého ramene na hřbetě: střed a poloosy.
PTERO_SHOULDER_DOME = ((6.5, -7.0), (4.2, 5.2))
# Tmavší hřbet jako u vlka: šířka pruhu jako díl šířky trupu a kolik světlosti trupu mu zůstane.
PTERO_SADDLE = ((0.62, 0.95), (0.52, 0.88), (0.42, 0.81), (0.32, 0.75), (0.22, 0.7))
PTERO_SADDLE_Y = (-14.0, 21.0)
# Krk se kreslí pod trup, hruď se k němu vpředu zúží.
PTERO_BODY = (
    (-16.0, 3.4),
    (-11.0, 7.6),
    (-4.0, 9.2),
    (3.0, 8.0),
    (10.0, 5.8),
    (16.0, 3.6),
    (20.0, 2.2),
    (23.0, 1.0),
)
PTERO_NECK = ((-12.0, 3.4), (-17.0, 3.1), (-22.0, 2.9))
# Oválná lebka za zúženým krkem a kratší zobák, aby se hlava shora četla jako hlava.
PTERO_HEAD = (
    (-22.5, 2.7),
    (-24.5, 6.0),
    (-28.0, 7.0),
    (-32.0, 6.2),
    (-36.0, 4.4),
    (-42.0, 3.0),
    (-48.0, 1.9),
    (-55.0, 0.7),
)
PTERO_HEAD_YAW = 2.0
PTERO_EYE = ((4.7, -28.5), 1.5)
PTERO_EYE_RIM = 0.45
# Noha pravé strany: kyčel, koleno, chodidlo. Kreslí se pod blánu a trup, vykukuje jen holeň a prsty.
PTERO_LEG: tuple[Point, ...] = ((2.5, 14.0), (4.0, 21.0), (4.6, 28.0))

# Kamenný ptakoještěr (ptakojester2). Kameny blány mají poloměr kolem PTERO_WING_STONE px,
# nejméně PTERO_WING_STONE_MIN. Kosti křídla a nohy jako FEMUR_STONES: od, do, poloměr a akcent.
PTERO_WING_STONE = 5.0
PTERO_WING_STONE_MIN = 1.6
PTERO_BONE_STONES = ((0.05, 0.95, 1.2, 0.0),)
PTERO_FINGER_STONES = ((0.03, 0.35, 1.2, 0.0), (0.37, 0.68, 1.2, 0.0), (0.7, 1.0, 1.2, 0.0))
# Kameny hlavy po ose: Y a poloměr, od týla po špičku zobáku.
PTERO_HEAD_STONES = ((-24.5, 5.0), (-29.0, 6.2), (-35.0, 4.6), (-41.0, 3.2), (-47.0, 2.2), (-52.5, 1.4))
# Kamenný ptakoještěr je o pětinu větší než původní.
PTERO_STONE_ZOOM = 1.2

# Tyranosaurus, asi 3,2 m od čenichu po špičku ocasu. Kyčle jsou ve středu plátna.
REX_CANVAS = 256
# Páteř trupu od šíje po špičku ocasu: Y a poloviční šířka v px.
REX_BODY = (
    (-62.0, 12.0),
    (-52.0, 14.0),
    (-40.0, 21.0),
    (-26.0, 25.0),
    (-10.0, 24.0),
    (4.0, 20.0),
    (16.0, 17.0),
    (34.0, 13.5),
    (54.0, 9.5),
    (74.0, 6.0),
    (92.0, 3.2),
    (106.0, 1.2),
)
# Hlava od zátylku po čenich, napojená na šíji. Nejširší je za očima, čenich je tupý.
REX_HEAD = (
    (-63.0, 14.0),
    (-68.0, 17.5),
    (-75.0, 17.0),
    (-84.0, 13.5),
    (-93.0, 10.5),
    (-100.0, 8.0),
    (-103.0, 5.5),
)
REX_NECK = -62.0
# Krk se od téhle Y stáčí proti kyčlím, ocas se od téhle Y vlní.
REX_NECK_FROM = -40.0
REX_TAIL_FROM = 6.0
REX_TAIL_LENGTH = 100.0
REX_TAIL_WAVE = 9.0
# Boční kývání kyčlí v px a natočení hlavy ve stupních.
REX_SWAY = 2.2
REX_HEAD_YAW = 3.0
# Kyčelní kloub a chodidlo v klidu, pravá strana.
REX_HIP = (17.0, 2.0)
REX_FOOT = (29.0, 2.0)
REX_STRIDE = 70.0
REX_PULL = 0.12
# Prsty od vnitřního, úhel od směru vpřed ve stupních a délka. Chodidlo se lehce stáčí ven.
REX_TOES = ((-26.0, 14.0), (0.0, 19.0), (26.0, 14.0))
REX_TOE_OUT = 8.0
# Pruhy přes hřbet: Y středu. Kraje pruhu zaostávají dozadu, pruh je krokev mířící vpřed.
REX_STRIPES = (-34.0, -22.0, -10.0, 4.0, 18.0, 32.0, 46.0, 60.0, 74.0)
REX_STRIPE_LAG = 3.5
# Ruka pravé strany: rameno, loket, dlaň.
REX_ARM: tuple[Point, ...] = ((14.0, -36.0), (24.5, -39.0), (21.0, -48.0))
REX_EYE = ((12.0, -74.0), 2.2)
REX_HORN = ((10.0, -78.0), (11.8, -82.0))
REX_NOSTRIL = ((3.6, -100.0), 1.1)
# Kamenný tyranosaurus (rex2). Kameny článků jako FEMUR_STONES: od, do, poloměr a akcent.
REX_LEG_STONES = ((0.05, 0.55, 1.0, 0.0), (0.5, 0.97, 0.95, 0.0))
REX_THIGH_STONES = ((0.0, 1.0, 1.0, 0.0),)
REX_TOE_STONES = ((0.1, 0.55, 1.0, 0.0), (0.55, 1.0, 1.0, 0.0))
REX_ARM_STONES = ((0.05, 0.95, 1.1, 0.0),)
# Kameny hlavy: střed (pravá strana, x 0 je na ose) a poloměr. Od zátylku k čenichu.
REX_HEAD_STONES = (
    ((0.0, -64.0), 12.0),
    ((9.0, -71.0), 8.5),
    ((0.0, -76.0), 11.0),
    ((6.5, -86.0), 7.0),
    ((0.0, -92.0), 8.5),
    ((0.0, -99.5), 6.0),
)

# Had, asi 1,6 m od čenichu po špičku ocasu. Délka s se měří po páteři od čenichu, v px.
SNAKE_CANVAS = 128
SNAKE_SNOUT = -42.0
# Poloviční šířka podle s: klínovitá hlava, užší krk, nejširší třetina těla, tenký ocas.
SNAKE_WIDTH = (
    (0.0, 1.8),
    (2.0, 3.0),
    (5.0, 4.1),
    (8.5, 4.8),
    (11.0, 4.1),
    (14.0, 2.9),
    (18.0, 2.9),
    (28.0, 3.6),
    (45.0, 4.3),
    (64.0, 4.0),
    (79.0, 3.1),
    (91.0, 1.8),
    (101.0, 0.5),
)
SNAKE_LENGTH = SNAKE_WIDTH[-1][0]
# Hlava a krk až po SNAKE_NECK jdou rovně a jen se natáčejí. Do SNAKE_RAISE je had zvednutý
# (vrstva 2), tělo ve vrstvě 1 začíná už u SNAKE_TUCK pod hlavou, aby se vrstvy neroztrhly.
SNAKE_NECK = 16.0
SNAKE_RAISE = 22.0
SNAKE_TUCK = 9.0
SNAKE_HEIGHT = 0.35
SNAKE_HEAD_YAW = 3.0
# Vlna stojí na zemi, had po ní klouže: za cyklus urazí SNAKE_WAVE px. Výchylka za krkem
# naběhne na délce SNAKE_RAMP a k ocasu ještě trochu roste.
SNAKE_WAVE = 50.0
SNAKE_AMPLITUDE = 15.0
SNAKE_RAMP = 30.0
# Kosočtverce na hřbetě: první a poslední střed (s), rozestup, poloviční délka a poloviční
# šířka jako díl šířky těla. Tmavý lem má tenhle poloměr.
SNAKE_DIAMONDS = (24.0, 88.0, 8.0, 3.3, 0.74)
SNAKE_RIM = 0.45
# Užší tělo než tohle má menší kosočtverce.
SNAKE_WIDE = 3.6
SNAKE_CROWN = 11.0
# Skvrny na bocích mezi kosočtverci: díl šířky těla od páteře, poloměr, síla akcentu.
SNAKE_SPOTS = (0.82, 0.85, 0.55)
# Oko a nozdra pravé strany: s, díl šířky těla od páteře a poloměr.
SNAKE_EYE = (6.0, 0.7, 1.15)
SNAKE_NOSTRIL = (1.6, 0.5, 0.45)
# Jazyk: délka před rozeklání, délka a rozevření hrotů ve stupních. Vymrští se dvakrát za cyklus.
SNAKE_TONGUE = (6.0, 2.6, 24.0)
# Kamenný had (had2): kameny těla mají poloměr SNAKE_STONE_SIZE šířky, střídavě vybočují
# o SNAKE_STONE_SWAY šířky do stran. Rozestup je větší z px a násobku šířky.
SNAKE_STONE_SIZE = 1.05
SNAKE_STONE_SWAY = 0.2
SNAKE_STONE_STEP = (1.8, 1.3)
SNAKE_STONE_STRETCH = 1.25
# Kameny hlavy a krku od krku k čenichu: s a poloměr jako díl šířky.
SNAKE_HEAD_STONES = ((20.0, 1.1), (15.5, 1.15), (10.5, 1.0), (6.5, 0.95), (2.6, 0.95))

# Kamenná koule (koule2). Tělo je o desetinu menší než pavoukovo, poloměr koule v px je stejný
# jako poloměr těla. Střed koule je ve středu plátna.
BALL_CANVAS = 80
BALL_BODY = round(0.45 * 0.9, 3)
BALL_R = BALL_BODY * PX_PER_METER
BALL_HEIGHT = 0.55
BALL_FRAMES = 24
# Kameny jsou rozložené po kouli rovnoměrně (Fibonacciho spirála), poloměr v px kolísá o 30 %.
# Kámen pod horizontem do -BALL_HIDE ještě vykukuje na obrysu.
BALL_STONES = 64
BALL_STONE_R = 6.0
BALL_HIDE = 0.2
# Světlost kamene podle výšky na kouli a ztmavení spodní vrstvy.
BALL_LIGHT = (0.42, 0.58)
BALL_LOW_DIM = 0.55
# Pravé oko: bod na kouli. Oko je šikmá mandle (poloosy v px), vnitřní koutek je níž na tváři,
# tedy víc vpředu, o BALL_EYE_TILT stupňů. Tmavý důlek je o BALL_SOCKET px větší.
BALL_EYE = (0.37, -0.69, 0.62)
BALL_EYE_SIZE = (4.2, 2.7)
BALL_EYE_TILT = 30.0
BALL_SOCKET = 1.1
# Zornice je svislá štěrbina: poloviční délka a poloměr v px.
BALL_PUPIL = (1.5, 0.45)
# Víčko uřízne oko rovnou hranou: výška hrany u vnitřního a vnějšího koutku jako díl výšky oka.
# U nosu zbude špička, ven se oko rozšíří do zamračeného klínu.
BALL_LID = (-0.05, 0.85)
# Obočí je protažený kámen na hraně víčka: posun nad hranu, poloměr a protažení.
BALL_BROW = (1.9, 2.5, 1.9)
# Obličej (oči a tlama) je pevná kamenná deska, která se netočí: čepička koule kolem směru
# BALL_FACE s úhlovým poloměrem BALL_FACE_ANGLE stupňů. Valící se kameny zajíždějí pod její okraj.
BALL_FACE = (0.0, -0.86, 0.5)
BALL_FACE_ANGLE = 40.0
# Deska má kameny hustší než zbytek koule (tolik bodů na celou kouli) a o kus světlejší.
BALL_FACE_DENSITY = 84
BALL_FACE_LIGHT = 1.08
# Deska i s očima a tlamou je vysunutá o tolik px dopředu a vpředu přečnívá přes obrys koule.
BALL_FACE_SHIFT = 3.0
# Na okraji, kde deska leží na kouli, deska na tolik px plynule průhlední a valící se kameny
# pod ní prosvítají. Kde deska přečnívá přes obrys koule, zůstane okraj ostrý.
BALL_FACE_FEATHER = 4.0
# Tlama úplně vpředu pod očima: bod na kouli, poloviční šířka a výška horního rtu v px a o kolik
# px klesnou koutky k přední straně (zamračení). Uvnitř žhne barvou očí, otevřená víc.
BALL_MOUTH = (0.0, -0.93, 0.37)
BALL_MOUTH_SIZE = (7.6, 1.6)
BALL_MOUTH_FROWN = 2.0
BALL_MOUTH_GLOW = (0.35, 0.9)
# Kousání: za cyklus BALL_BITES kousnutí (celé číslo, ať smyčka nemá skok). Spodní čelist
# klesá dopředu, výška spodního rtu zavřené a otevřené tlamy v px. Otvírá se pomalu a cvakne
# rychle: otevřená je nejvíc v BALL_BITE_PEAK kousnutí.
BALL_BITES = 2
BALL_JAW = (0.8, 5.6)
BALL_BITE_PEAK = 0.7
# Hřbetní hřeben: nepravidelný pás kamenů podél horní osy koule zezadu přes vršek až pod obličej.
# Valí se stejným směrem jako koule, ale pomaleji: za cyklus o BALL_RIDGE_SPEED otáčky. Pás se
# skládá z 1 / BALL_RIDGE_SPEED stejných úseků, za cyklus se posune právě o jeden, takže smyčka
# nemá skok. V úseku je BALL_RIDGE_STONES kamenů rozházených podél i napříč.
BALL_RIDGE_SPEED = 0.25
BALL_RIDGE_STONES = 13
# Poloviční šířka pásu jako díl poloměru: střed a zvlnění okraje.
BALL_RIDGE_WIDTH = (0.38, 0.07)
# Kameny: největší vybočení do strany (díl poloměru), poloměr v px od do a světlost od do.
BALL_RIDGE_ACROSS = 0.26
BALL_RIDGE_SIZE = (4.0, 7.0)
BALL_RIDGE_LIGHT = (0.88, 1.15)
# Pás vede jen od obličeje přes vršek kousek za střed koule, zadní část je bez něj. Konec je
# BALL_RIDGE_END poloměru za středem a pás k němu plynule průhlední na BALL_RIDGE_FADE px.
BALL_RIDGE_END = 0.2
BALL_RIDGE_FADE = 6.0
# Zuby: počet nahoře a dole, délka v px. Zavřené se zaklesnou do sebe.
BALL_TEETH = (4, 3, 2.4)
# Zuby jsou obarvené akcentem jako kresba ostatních golemů.
BALL_TEETH_ACCENT = 0.7

# Druhy. Materiály druhu a jejich barvy jsou v gen_crystal.MATERIALS.
# preview_shadow je obdélník elipsy stínu jen v náhledech, ve hře se nekreslí.
# Vrstva se shadow je skutečný stín v atlasu. info se zkopíruje do katalogu.
# zoom zmenší tvora při ukládání do atlasu, cycle_meters a body_meters už počítají se zmenšením.
# frames je počet snímků jednoho cyklu. preview_cycle_ms je délka cyklu v náhledových GIFech.
# Pohyb ve hře: wander_meters je volné toulání, chase_meters honička za postavou, která nese
# materiál druhu (postava běží 4,5 m/s), násobí ji monster_speed materiálu z gen_crystal.
# body_meters je poloměr těla pro překážky a dotek. height_meters je výška tvora: skákající ho
# přeskočí, když skočí aspoň tak vysoko (postava a vesničan měří 1,8 m). jump_meters je výška
# překážky nebo tvora, přes kterou druh skočí, 0 neskáče.
MONSTERS = {
    # Původní had. Ve hře ho nahradil had2, žádný materiál ho nemá, náhledy kreslí v preview_materials.
    "had": {
        "canvas": SNAKE_CANVAS,
        "preview_shadow": ((-16.0, -44.0), (16.0, 40.0)),
        "preview_materials": ("piskovec", "sira"),
        "layers": {
            1: {"height": 0.0, "file": "layer_1.png"},
            2: {"height": SNAKE_HEIGHT, "file": "layer_2.png"},
        },
        "cycle_meters": SNAKE_WAVE / PX_PER_METER,
        "frames": 16,
        "preview_cycle_ms": 900,
        "wander_meters": 0.8,
        "chase_meters": 3.7,
        "body_meters": 0.4,
        "height_meters": 0.3,
        "eye": "FF5A3C",
    },
    # Kamenný had místo hada. Zvuky má hadí. preview_materials ukážou třpyt i na lesklejších kamenech.
    "had2": {
        "canvas": SNAKE_CANVAS,
        "preview_shadow": ((-16.0, -44.0), (16.0, 40.0)),
        "preview_materials": ("kremen", "zlato"),
        "info": {"shader": "stone", "sound": "had"},
        "layers": {
            1: {"height": 0.0, "file": "layer_1.png"},
            2: {"height": SNAKE_HEIGHT, "file": "layer_2.png"},
        },
        "cycle_meters": SNAKE_WAVE / PX_PER_METER,
        "frames": 16,
        "preview_cycle_ms": 900,
        "wander_meters": 0.8,
        "chase_meters": 3.7,
        "body_meters": 0.4,
        "height_meters": 0.3,
        "eye": "FF5A3C",
    },
    # Původní pavouk. Ve hře ho nahradil pavouk2, žádný materiál ho nemá, náhledy kreslí v preview_materials.
    "pavouk": {
        "canvas": SPIDER_CANVAS,
        "preview_shadow": ((-15.0, -12.0), (15.0, 40.0)),
        "preview_materials": ("lavovy", "grafit"),
        "layers": {
            1: {"height": 0.0, "file": "layer_1.png"},
            2: {"height": 0.5, "file": "layer_2.png"},
        },
        "cycle_meters": 2.0 * STRIDE / PX_PER_METER,
        "frames": 8,
        "wander_meters": 0.8,
        "chase_meters": 4.1,
        "body_meters": 0.45,
        "height_meters": 0.5,
        "eye": "F04A2C",
    },
    # Kamenný golem místo pavouka. Semínka třpytu jsou ve zvláštním atlasu, hra ho kreslí
    # shaderem stone. Zvuky má pavoukovy. preview_materials ukážou třpyt i na lesklejších kamenech.
    "pavouk2": {
        "canvas": SPIDER_CANVAS,
        "preview_shadow": ((-15.0, -12.0), (15.0, 40.0)),
        "preview_materials": ("lavovy", "grafit", "magnetit", "stribro", "diamant"),
        "info": {"shader": "stone", "sound": "pavouk"},
        "layers": {
            1: {"height": 0.0, "file": "layer_1.png"},
            2: {"height": 0.5, "file": "layer_2.png"},
        },
        "cycle_meters": 2.0 * STRIDE / PX_PER_METER,
        "frames": 8,
        "wander_meters": 0.8,
        "chase_meters": 4.1,
        "body_meters": 0.45,
        "height_meters": 0.5,
        "eye": "F04A2C",
    },
    # Původní vlk. Ve hře ho nahradil vlk2, žádný materiál ho nemá, náhledy kreslí v preview_materials.
    "vlk": {
        "canvas": WOLF_CANVAS,
        "preview_materials": ("magnetit", "kremen", "stribro"),
        "preview_shadow": ((-17.0, -46.0), (17.0, 30.0)),
        "layers": {
            1: {"height": 0.0, "file": "layer_1.png"},
            2: {"height": round(0.75 * WOLF_ZOOM, 3), "file": "layer_2.png"},
        },
        "zoom": WOLF_ZOOM,
        "cycle_meters": 2.0 * WOLF_STRIDE * WOLF_ZOOM / PX_PER_METER,
        "frames": 8,
        "wander_meters": 1.0,
        "chase_meters": 4.5,
        "body_meters": round(0.45 * WOLF_ZOOM, 3),
        "height_meters": 0.7,
        "jump_meters": 2.1,
        "eye": "FFD23A",
    },
    # Kamenný vlk místo vlka, rychlejší než původní. Zvuky má vlčí.
    "vlk2": {
        "canvas": WOLF_CANVAS,
        "info": {"shader": "stone", "sound": "vlk"},
        "preview_shadow": ((-17.0, -46.0), (17.0, 30.0)),
        "layers": {
            1: {"height": 0.0, "file": "layer_1.png"},
            2: {"height": round(0.75 * WOLF_ZOOM, 3), "file": "layer_2.png"},
        },
        "zoom": WOLF_ZOOM,
        "cycle_meters": 2.0 * WOLF_STRIDE * WOLF_ZOOM / PX_PER_METER,
        "frames": 8,
        "wander_meters": 1.0,
        "chase_meters": 5.0,
        "body_meters": round(0.45 * WOLF_ZOOM, 3),
        "height_meters": 0.7,
        "jump_meters": 2.1,
        "eye": "FFD23A",
    },
    # Původní ptakoještěr. Ve hře ho nahradil ptakojester2, žádný materiál ho nemá, náhledy kreslí v preview_materials.
    "ptakojester": {
        "canvas": PTERO_CANVAS,
        "preview_materials": ("rubin", "safir", "diamant"),
        "preview_shadow": None,
        "layers": {
            1: {"height": 0.0, "file": "layer_1.png", "shadow": True},
            2: {"height": PTERO_HEIGHT, "file": "layer_2.png"},
        },
        "cycle_meters": PTERO_CYCLE,
        "frames": PTERO_FRAMES,
        "info": {"flying": True, "glide_frame": PTERO_GLIDE_FRAME},
        "preview_cycle_ms": 1600,
        "wander_meters": 1.5,
        "chase_meters": 5.0,
        "body_meters": 0.8,
        "height_meters": 1.0,
        "eye": "7DF2FF",
    },
    # Kamenný ptakoještěr místo ptakoještěra, o pětinu větší a rychlejší. Zvuky má ptakoještěří.
    "ptakojester2": {
        "canvas": PTERO_CANVAS,
        "zoom": PTERO_STONE_ZOOM,
        "preview_shadow": None,
        "layers": {
            1: {"height": 0.0, "file": "layer_1.png", "shadow": True},
            2: {"height": PTERO_HEIGHT, "file": "layer_2.png"},
        },
        "cycle_meters": PTERO_CYCLE * PTERO_STONE_ZOOM,
        "frames": PTERO_FRAMES,
        "info": {"flying": True, "glide_frame": PTERO_GLIDE_FRAME, "shader": "stone", "sound": "ptakojester"},
        "preview_cycle_ms": 1600,
        "wander_meters": 1.5,
        "chase_meters": 5.5,
        "body_meters": round(0.8 * PTERO_STONE_ZOOM, 3),
        "height_meters": 1.0,
        "eye": "7DF2FF",
    },
    # Původní tyranosaurus. Ve hře ho nahradil rex2, žádný materiál ho nemá, náhledy kreslí v preview_materials.
    "tyranosaurus": {
        "canvas": REX_CANVAS,
        "preview_materials": ("jantar", "smaragd", "zlato"),
        "preview_shadow": ((-28.0, -72.0), (28.0, 70.0)),
        "layers": {
            1: {"height": 0.0, "file": "layer_1.png"},
            2: {"height": 1.2, "file": "layer_2.png"},
        },
        "cycle_meters": 2.0 * REX_STRIDE / PX_PER_METER,
        "frames": 16,
        "wander_meters": 0.8,
        "chase_meters": 5.3,
        "body_meters": 0.55,
        "height_meters": 3.0,
        "jump_meters": 4.1,
        "eye": "FFC21A",
    },
    # Kamenný tyranosaurus místo tyranosaura, rychlejší než původní. Zvuky má tyranosauří.
    "rex2": {
        "canvas": REX_CANVAS,
        "info": {"shader": "stone", "sound": "tyranosaurus"},
        "preview_shadow": ((-28.0, -72.0), (28.0, 70.0)),
        "layers": {
            1: {"height": 0.0, "file": "layer_1.png"},
            2: {"height": 1.2, "file": "layer_2.png"},
        },
        "cycle_meters": 2.0 * REX_STRIDE / PX_PER_METER,
        "frames": 16,
        "wander_meters": 0.8,
        "chase_meters": 5.5,
        "body_meters": 0.55,
        "height_meters": 3.0,
        "jump_meters": 4.1,
        "eye": "FFC21A",
    },
    # Kamenná koule místo kamenného vlka, o desetinu menší než pavouk. Za cyklus se jednou otočí.
    # Zvuky má vlastní, kamenné dunění.
    "koule2": {
        "canvas": BALL_CANVAS,
        "preview_shadow": ((-BALL_R * 1.05, -BALL_R * 0.9), (BALL_R * 1.05, BALL_R * 1.15)),
        "preview_materials": ("lavovy", "zlato"),
        "info": {"shader": "stone", "sound": "koule"},
        "layers": {
            1: {"height": 0.0, "file": "layer_1.png"},
            2: {"height": BALL_HEIGHT, "file": "layer_2.png"},
        },
        "cycle_meters": math.tau * BALL_R / PX_PER_METER,
        "frames": BALL_FRAMES,
        "preview_cycle_ms": 900,
        "wander_meters": 1.0,
        "chase_meters": 4.5,
        "body_meters": BALL_BODY,
        "height_meters": round(2.0 * BALL_BODY, 3),
        "eye": "FF3A1A",
    },
}


def byte(value: float) -> int:
    return max(0, min(255, round(value * 255)))


def lerp(a: Point, b: Point, t: float) -> Point:
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def rotate(point: Point, angle: float) -> Point:
    c, s = math.cos(angle), math.sin(angle)
    return (point[0] * c - point[1] * s, point[0] * s + point[1] * c)


def mirror(point: Point, side: float) -> Point:
    return (point[0] * side, point[1])


def spine_normals(spine: list[Point]) -> list[Point]:
    normals = []
    for index in range(len(spine)):
        a = spine[max(index - 1, 0)]
        b = spine[min(index + 1, len(spine) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy) or 1.0
        normals.append((-dy / length, dx / length))
    return normals


class Layer:
    """Masky jedné vrstvy ve čtyřnásobném rozlišení: světlost, akcent, oči, krytí.

    Pozdější tvar přepíše dřívější. None nechá kanál, jak byl.
    """

    def __init__(self, canvas: int) -> None:
        self.canvas = canvas
        size = canvas * SS
        self.channels = [Image.new("L", (size, size), 0) for _ in range(4)]
        self.draws = [ImageDraw.Draw(channel) for channel in self.channels]
        # Semínka odlesků kamenné příšery (jas = fáze), jdou do zvláštního atlasu.
        self.spark = Image.new("L", (size, size), 0)
        self.spark_draw = ImageDraw.Draw(self.spark)

    def px(self, point: Point) -> Point:
        return ((self.canvas / 2 + point[0]) * SS, (self.canvas / 2 + point[1]) * SS)

    def _fill(self, shade: float | None, accent: float | None, eye: float | None):
        for draw, value in zip(self.draws, (shade, accent, eye, 1.0)):
            if value is not None:
                yield draw, byte(value)
        # Tvar zakryje semínka pod sebou.
        yield self.spark_draw, 0

    def polygon(self, points: list[Point], shade: float | None, accent: float | None = 0.0, eye: float | None = 0.0) -> None:
        outline = [self.px(point) for point in points]
        for draw, value in self._fill(shade, accent, eye):
            draw.polygon(outline, fill=value)

    def disk(self, center: Point, radius: float, shade: float | None, accent: float | None = 0.0, eye: float | None = 0.0) -> None:
        x, y = self.px(center)
        r = radius * SS
        for draw, value in self._fill(shade, accent, eye):
            draw.ellipse((x - r, y - r, x + r, y + r), fill=value)

    def capsule(
        self,
        start: Point,
        end: Point,
        r0: float,
        r1: float,
        shade: float | None,
        accent: float | None = 0.0,
        eye: float | None = 0.0,
    ) -> None:
        ax, ay = self.px(start)
        bx, by = self.px(end)
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / length, dx / length
        a, b = r0 * SS, r1 * SS
        outline = [(ax + nx * a, ay + ny * a), (bx + nx * b, by + ny * b), (bx - nx * b, by - ny * b), (ax - nx * a, ay - ny * a)]
        for draw, value in self._fill(shade, accent, eye):
            draw.polygon(outline, fill=value)
            draw.ellipse((ax - a, ay - a, ax + a, ay + a), fill=value)
            draw.ellipse((bx - b, by - b, bx + b, by + b), fill=value)

    def dome(self, center: Point, radii: Point, angle: float, low: float, high: float) -> None:
        """Elipsa osvětlená shora. Světlo je kolmé, takže otočení uzlu stínům nevadí."""
        cx, cy = self.px(center)
        rx, ry = radii[0] * SS, radii[1] * SS
        c, s = math.cos(angle), math.sin(angle)
        reach = max(rx, ry)
        limit = self.canvas * SS
        x0, x1 = max(0, math.floor(cx - reach)), min(limit, math.ceil(cx + reach))
        y0, y1 = max(0, math.floor(cy - reach)), min(limit, math.ceil(cy + reach))
        shade, accent, eye, alpha = (channel.load() for channel in self.channels)
        spark = self.spark.load()
        for py in range(y0, y1):
            dy = py + 0.5 - cy
            for px in range(x0, x1):
                dx = px + 0.5 - cx
                u = (dx * c + dy * s) / rx
                v = (-dx * s + dy * c) / ry
                r2 = u * u + v * v
                if r2 > 1.0:
                    continue
                shade[px, py] = byte(low + (high - low) * (1.0 - r2) ** 0.4)
                accent[px, py] = 0
                eye[px, py] = 0
                alpha[px, py] = 255
                spark[px, py] = 0

    def tube(
        self,
        spine: list[Point],
        widths: list[float],
        low: float,
        high: float,
        accent: float | None = 0.0,
        depth: float = 1.0,
    ) -> None:
        """Trubice podél páteře se zaoblenými konci, osvětlená shora jako dome.

        Skládá se ze soustředných pásů, vnitřní pás je nejsvětlejší. depth je šířka
        vůči trubici pod ní: stín pak navazuje, jako by šlo o její střední pruh.
        """
        normals = spine_normals(spine)
        for band in range(TUBE_BANDS):
            outer = 1.0 - band / TUBE_BANDS
            mid = (1.0 - (band + 0.5) / TUBE_BANDS) * depth
            value = low + (high - low) * (1.0 - mid * mid) ** 0.4
            left = [(p[0] + n[0] * w * outer, p[1] + n[1] * w * outer) for p, n, w in zip(spine, normals, widths)]
            right = [(p[0] - n[0] * w * outer, p[1] - n[1] * w * outer) for p, n, w in zip(spine, normals, widths)]
            self.polygon(left + right[::-1], value, accent)
            self.disk(spine[0], widths[0] * outer, value, accent)
            self.disk(spine[-1], widths[-1] * outer, value, accent)

    def blend(self, other: Layer, mask: Image.Image) -> None:
        """Vmíchá jinou vrstvu přes tuhle. mask (L ve čtyřnásobném rozlišení) je krytí other,
        násobí se jejím vlastním krytím. Semínka odlesků se převezmou, kde other převažuje."""
        cover = ImageChops.multiply(mask, other.channels[3])
        for index in range(3):
            self.channels[index] = Image.composite(other.channels[index], self.channels[index], cover)
        self.channels[3] = ImageChops.lighter(self.channels[3], cover)
        self.spark = Image.composite(other.spark, self.spark, cover.point(lambda value: 255 if value >= 128 else 0))
        self.draws = [ImageDraw.Draw(channel) for channel in self.channels]
        self.spark_draw = ImageDraw.Draw(self.spark)

    def shadow(self, blur: float = 1.2) -> Layer:
        """Stín vrstvy na zemi: jen krytí, rozmazané o blur px."""
        out = Layer(self.canvas)
        out.channels[3] = self.channels[3].filter(ImageFilter.GaussianBlur(blur * SS))
        out.draws[3] = ImageDraw.Draw(out.channels[3])
        return out


def foot_at(hip: Point, rest: Point, phase: float, stride: float, pull: float) -> tuple[Point, float]:
    """První polovina cyklu na zemi, druhá ve vzduchu. Vrací chodidlo a zvednutí 0 až 1."""
    if phase < 0.5:
        return (rest[0], rest[1] - stride / 2 + stride * phase / 0.5), 0.0
    s = (phase - 0.5) / 0.5
    ease = s * s * (3.0 - 2.0 * s)
    lift = math.sin(math.pi * s)
    foot = (rest[0], rest[1] + stride / 2 - stride * ease)
    return lerp(foot, hip, pull * lift), lift


def height_shade(z: float) -> float:
    return 0.12 + 0.78 * max(0.0, min(1.0, z / TOP_Z))


def stroke(
    layer: Layer,
    start: Point,
    end: Point,
    z0: float,
    z1: float,
    r0: float,
    r1: float,
    bands: tuple[tuple[float, float], ...] = (),
    steps: int = 10,
) -> None:
    """Článek končetiny po kouscích, každý má světlost podle své výšky."""
    for step in range(steps):
        t0, t1 = step / steps, (step + 1) / steps
        mid = (t0 + t1) * 0.5
        accent = 0.85 if any(lo <= mid < hi for lo, hi in bands) else 0.0
        layer.capsule(
            lerp(start, end, t0),
            lerp(start, end, t1),
            r0 + (r1 - r0) * t0,
            r0 + (r1 - r0) * t1,
            height_shade(z0 + (z1 - z0) * mid),
            accent,
        )


def leg_phase(index: int, side: float, t: float) -> float:
    group = (index + (1 if side > 0 else 0)) % 2
    return (t + 0.5 * group) % 1.0


def knee_of(hip: Point, foot: Point, foot_z: float, femur: float, tibia: float, bend: float) -> tuple[Point, float]:
    """Koleno ve svislé rovině kyčle a chodidla, shora jen kousek vybočené."""
    dx, dy = foot[0] - hip[0], foot[1] - hip[1]
    flat = math.hypot(dx, dy) or 1.0
    rise = foot_z - HIP_Z
    reach = min(math.hypot(flat, rise), (femur + tibia) * 0.999)
    cos_hip = (femur * femur + reach * reach - tibia * tibia) / (2.0 * femur * reach)
    angle = math.atan2(rise, flat) + math.acos(max(-1.0, min(1.0, cos_hip)))
    along = femur * math.cos(angle)
    ux, uy = dx / flat, dy / flat
    nx, ny = -uy, ux
    if ny * bend < 0.0:
        nx, ny = -nx, -ny
    knee = (hip[0] + ux * along + nx * abs(bend), hip[1] + uy * along + ny * abs(bend))
    return knee, HIP_Z + femur * math.sin(angle)


def paint_leg(layer: Layer, index: int, side: float, t: float) -> None:
    hip_r, rest_r, bend = LEGS[index]
    hip, rest = mirror(hip_r, side), mirror(rest_r, side)
    reach = math.dist(hip, rest)
    foot, lift = foot_at(hip, rest, leg_phase(index, side, t), STRIDE, PULL)
    knee, knee_z = knee_of(hip, foot, LIFT * lift, reach * FEMUR, reach * TIBIA, bend)
    r_hip, r_knee, r_tip = LEG_RADIUS
    layer.capsule(lerp(hip, PROSOMA, TUCK), hip, r_hip, r_hip, height_shade(HIP_Z))
    stroke(layer, hip, knee, HIP_Z, knee_z, r_hip, r_knee)
    stroke(layer, knee, foot, knee_z, LIFT * lift, r_knee, r_tip, LEG_BANDS)


def paint_palp(layer: Layer, side: float, t: float) -> None:
    points = [mirror(point, side) for point in PALP]
    wiggle = PALP_WIGGLE * math.sin(math.tau * t + (0.0 if side > 0 else math.pi))
    points[3] = (points[3][0], points[3][1] + wiggle)
    points[2] = (points[2][0], points[2][1] + wiggle * 0.5)
    r_hip, r_knee, r_tip = PALP_RADIUS
    layer.capsule(points[0], points[1], r_hip, r_hip, height_shade(PALP_Z[0]))
    stroke(layer, points[1], points[2], PALP_Z[1], PALP_Z[2], r_hip, r_knee, steps=4)
    stroke(layer, points[2], points[3], PALP_Z[2], PALP_Z[3], r_knee, r_tip, steps=4)


def abdomen_point(center: Point, angle: float, local: Point) -> Point:
    offset = rotate((local[0] * ABDOMEN_R[0], local[1] * ABDOMEN_R[1]), angle)
    return (center[0] + offset[0], center[1] + offset[1])


def paint_abdomen_marks(layer: Layer, center: Point, sway: float) -> None:
    """Kříž a krokve na zadečku. Světlost nechá, jak je, takže na kamenech zůstanou plošky."""
    for local, radius, weight in CROSS:
        layer.disk(abdomen_point(center, sway, local), radius, None, weight)
    for along in CHEVRONS:
        width = 0.5 * (1.0 - along * 0.45)
        tip = abdomen_point(center, sway, (0.0, along + 0.07))
        for side in (-1.0, 1.0):
            arm = abdomen_point(center, sway, (side * width, along - 0.07))
            layer.capsule(arm, tip, 0.9, 0.9, None, 0.6)


def paint_spider_body(layer: Layer, t: float) -> None:
    for side in (-1.0, 1.0):
        layer.dome((side * 2.6, -13.2), (2.3, 3.2), 0.0, 0.15, 0.45)
        layer.disk((side * 1.7, -16.0), 0.9, 0.06)
    layer.dome(PROSOMA, PROSOMA_R, 0.0, 0.28, 0.86)
    layer.capsule((0.0, -4.5), (0.0, 7.5), 1.5, 1.0, None, 0.65)
    for side in (-1.0, 1.0):
        for center, radius in EYES:
            layer.disk(mirror(center, side), radius, None, 0.0, 1.0)

    sway = math.radians(SWAY) * math.sin(math.tau * t)
    offset = rotate((ABDOMEN[0] - PEDICEL[0], ABDOMEN[1] - PEDICEL[1]), sway)
    center = (PEDICEL[0] + offset[0], PEDICEL[1] + offset[1])
    layer.dome(center, ABDOMEN_R, sway, 0.22, 1.0)
    paint_abdomen_marks(layer, center, sway)


def spider_layers(t: float) -> dict[int, Layer]:
    legs, body = Layer(SPIDER_CANVAS), Layer(SPIDER_CANVAS)
    for index in reversed(range(len(LEGS))):
        for side in (-1.0, 1.0):
            paint_leg(legs, index, side, t)
    for side in (-1.0, 1.0):
        paint_palp(legs, side, t)
    paint_spider_body(body, t)
    return {1: legs, 2: body}


def facet_factor(cell: int, facet: int) -> float:
    """Pevná náhodná hodnota 0 až 1 pro plošku kamene, stejná ve všech snímcích."""
    value = math.sin(cell * 12.9898 + facet * 78.233) * 43758.5453
    return value - math.floor(value)


def stone_outline(
    center: Point, radius: float, angle: float, cell: int, grow: float = 0.0, stretch: float = 1.0
) -> list[Point]:
    """Obrys kamene: nepravidelný mnohoúhelník, poloměr vrcholů kolísá podle cell.

    stretch protáhne kámen podél směru angle, grow ho zvětší o tolik px.
    """
    sides = STONE_SIDES[0] + cell % (STONE_SIDES[1] - STONE_SIDES[0] + 1)
    turn = facet_factor(cell, 11) * math.tau
    c, s = math.cos(angle), math.sin(angle)
    points = []
    for corner in range(sides):
        a = turn + math.tau * (corner + 0.35 * (facet_factor(cell, 20 + corner) - 0.5)) / sides
        r = radius * (0.78 + 0.3 * facet_factor(cell, 40 + corner))
        u = math.cos(a) * (r * stretch + grow)
        v = math.sin(a) * (r + grow)
        points.append((center[0] + u * c - v * s, center[1] + u * s + v * c))
    return points


def paint_stone(
    layer: Layer,
    center: Point,
    radius: float,
    angle: float,
    cell: int,
    light: float,
    spark: float = 0.0,
    stretch: float = 1.0,
    accent: float = 0.0,
) -> None:
    """Kámen shora jako krystaly ve hře: tmavý lem, zkosené plošky po obvodu, plochý vrchol.

    spark je šance, že kámen dostane semínko třpytu na vrcholové plošce. accent obarví
    plošky barvou kresby, světlost plošek zůstane.
    """
    outer = stone_outline(center, radius, angle, cell, stretch=stretch)
    inner = [lerp(center, point, STONE_TOP) for point in outer]
    layer.polygon(stone_outline(center, radius, angle, cell, STONE_RIM, stretch), 0.05)
    for index in range(len(outer)):
        following = (index + 1) % len(outer)
        facet = STONE_FACET[0] + (STONE_FACET[1] - STONE_FACET[0]) * facet_factor(cell, index)
        layer.polygon([outer[index], outer[following], inner[following], inner[index]], light * facet, accent)
    layer.polygon(inner, min(1.0, light * 1.1), accent)
    if facet_factor(cell, 77) < spark:
        x, y = layer.px(lerp(center, outer[cell % len(outer)], 0.35))
        r = SPARK_RADIUS * SS
        # Fáze 0,1 až 1. Pod 0,045 ji shader nebere jako semínko.
        layer.spark_draw.ellipse((x - r, y - r, x + r, y + r), fill=byte(0.1 + 0.9 * facet_factor(cell, 78)))


def paint_stone_heap(
    layer: Layer,
    stones: tuple[tuple[Point, float], ...],
    center: Point,
    radii: Point,
    angle: float,
    first_cell: int,
) -> None:
    """Část těla z kamenů. Pod nimi je tmavé jádro, které prosvítá mezerami.

    Polohy jsou v poloměrech části, takže se kameny s ní otáčejí jako jeden kus.
    """
    layer.dome(center, (radii[0] * 0.92, radii[1] * 0.92), angle, 0.04, 0.16)
    order = sorted(range(len(stones)), key=lambda index: -math.hypot(*stones[index][0]))
    for index in order:
        local, radius = stones[index]
        offset = rotate((local[0] * radii[0], local[1] * radii[1]), angle)
        lit = 1.0 - min(1.0, local[0] ** 2 + local[1] ** 2)
        point = (center[0] + offset[0], center[1] + offset[1])
        paint_stone(layer, point, radius, angle, first_cell + index, 0.6 + 0.4 * lit ** 0.4, SPARK_BODY)


def stone_segment(
    layer: Layer,
    start: Point,
    end: Point,
    z0: float,
    z1: float,
    r0: float,
    r1: float,
    stones: tuple[tuple[float, float, float, float], ...],
    cell: int,
) -> None:
    """Článek končetiny jako řada protažených kamenů na tmavém jádru."""
    layer.capsule(start, end, r0 * 0.6, r1 * 0.6, 0.05)
    angle = math.atan2(end[1] - start[1], end[0] - start[0])
    length = math.dist(start, end)
    for piece, (t0, t1, size, accent) in enumerate(stones):
        mid = (t0 + t1) * 0.5
        radius = (r0 + (r1 - r0) * mid) * size
        stretch = max(1.0, min(STONE_STRETCH, (t1 - t0) * length * 0.5 / radius))
        light = height_shade(z0 + (z1 - z0) * mid) * 1.15
        paint_stone(layer, lerp(start, end, mid), radius, angle, cell * 7 + piece, light, SPARK_LEG, stretch, accent)


def paint_golem_leg(layer: Layer, index: int, side: float, t: float) -> None:
    hip_r, rest_r, bend = LEGS[index]
    hip, rest = mirror(hip_r, side), mirror(rest_r, side)
    reach = math.dist(hip, rest)
    foot, lift = foot_at(hip, rest, leg_phase(index, side, t), STRIDE, PULL)
    knee, knee_z = knee_of(hip, foot, LIFT * lift, reach * FEMUR, reach * TIBIA, bend)
    r_hip, r_knee, r_tip = LEG_RADIUS
    cell = 100 + index * 2 + (1 if side > 0 else 0)
    layer.capsule(lerp(hip, PROSOMA, TUCK), hip, r_hip, r_hip, 0.05)
    stone_segment(layer, hip, knee, HIP_Z, knee_z, r_hip, r_knee, FEMUR_STONES, cell)
    stone_segment(layer, knee, foot, knee_z, LIFT * lift, r_knee, r_tip, TIBIA_STONES, cell + 20)
    paint_stone(layer, knee, STONE_KNEE, 0.0, 300 + cell, height_shade(knee_z) * 1.15, accent=STONE_KNEE_ACCENT)


def paint_golem_palp(layer: Layer, side: float, t: float) -> None:
    points = [mirror(point, side) for point in PALP]
    wiggle = PALP_WIGGLE * math.sin(math.tau * t + (0.0 if side > 0 else math.pi))
    points[3] = (points[3][0], points[3][1] + wiggle)
    points[2] = (points[2][0], points[2][1] + wiggle * 0.5)
    r_hip, r_knee, r_tip = PALP_RADIUS
    cell = 200 + (1 if side > 0 else 0)
    stone_segment(layer, points[1], points[2], PALP_Z[1], PALP_Z[2], r_hip, r_knee, PALP_STONES, cell)
    stone_segment(layer, points[2], points[3], PALP_Z[2], PALP_Z[3], r_knee, r_tip, PALP_STONES, cell + 2)


def golem_layers(t: float) -> dict[int, Layer]:
    """Kamenný golem: všechno z kamenů, jen oči svítí mezi nimi."""
    legs, body = Layer(SPIDER_CANVAS), Layer(SPIDER_CANVAS)
    for index in reversed(range(len(LEGS))):
        for side in (-1.0, 1.0):
            paint_golem_leg(legs, index, side, t)
    for side in (-1.0, 1.0):
        paint_golem_palp(legs, side, t)
    for side in (-1.0, 1.0):
        center, radius = FANG_STONE
        paint_stone(body, mirror(center, side), radius, math.pi / 2, 400 + (1 if side > 0 else 0), 0.55)
    paint_stone_heap(body, PROSOMA_STONES, PROSOMA, PROSOMA_R, 0.0, 500)
    body.capsule((0.0, -4.5), (0.0, 7.5), 1.5, 1.0, None, 0.65)
    for side in (-1.0, 1.0):
        for center, radius in EYES:
            body.disk(mirror(center, side), radius, None, 0.0, 1.0)
    sway = math.radians(SWAY) * math.sin(math.tau * t)
    offset = rotate((ABDOMEN[0] - PEDICEL[0], ABDOMEN[1] - PEDICEL[1]), sway)
    center = (PEDICEL[0] + offset[0], PEDICEL[1] + offset[1])
    paint_stone_heap(body, STONES, center, ABDOMEN_R, sway, 600)
    paint_abdomen_marks(body, center, sway)
    return {1: legs, 2: body}


def profile(points: tuple[Point, ...], step: float = 2.0) -> list[Point]:
    """Hustá páteř z řídkých bodů (Y, poloviční šířka). Šířka mezi body plyne jako Catmull-Rom."""
    out = []
    last = len(points) - 1
    for index in range(last):
        y0, y1 = points[index][0], points[index + 1][0]
        w0 = points[max(index - 1, 0)][1]
        w1, w2 = points[index][1], points[index + 1][1]
        w3 = points[min(index + 2, last)][1]
        count = max(1, math.ceil(abs(y1 - y0) / step))
        for k in range(count):
            s = k / count
            width = 0.5 * (
                2.0 * w1
                + (w2 - w0) * s
                + (2.0 * w0 - 5.0 * w1 + 4.0 * w2 - w3) * s * s
                + (3.0 * w1 - w0 - 3.0 * w2 + w3) * s * s * s
            )
            out.append((y0 + (y1 - y0) * s, width))
    out.append(points[-1])
    return out


def line(start: Point, end: Point, count: int = 6) -> list[Point]:
    return [lerp(start, end, k / (count - 1)) for k in range(count)]


def nearest(dense: list[Point], y: float) -> int:
    return min(range(len(dense)), key=lambda index: abs(dense[index][0] - y))


def fringe(
    layer: Layer,
    spine: list[Point],
    widths: list[float],
    first: int,
    last: int,
    count: int,
    length: float,
    shade: float,
    accent: float = 0.0,
    lean: float = 0.6,
    reach: float = 0.8,
) -> None:
    """Chomáče srsti z okraje trubice ven, nakloněné dozadu. Trubice se kreslí až po nich."""
    normals = spine_normals(spine)
    for side in (-1.0, 1.0):
        for k in range(count):
            index = min(len(spine) - 1, round(first + (last - first) * (k + 0.5) / count))
            (px, py), (nx, ny), width = spine[index], normals[index], widths[index]
            nx, ny = nx * side, ny * side
            size = length * (0.7 + 0.1 * ((k * 7 + (3 if side > 0 else 0)) % 4))
            half = size * 0.55
            edge = (px + nx * width * reach, py + ny * width * reach)
            tip = (px + nx * (width + size), py + ny * (width + size) + lean * size)
            base_a = (edge[0] + ny * half, edge[1] - nx * half)
            base_b = (edge[0] - ny * half, edge[1] + nx * half)
            layer.polygon([base_a, tip, base_b], shade, accent)


def paint_paw(layer: Layer, paw: Point, lift: float) -> None:
    raise_by = 0.25 * lift
    layer.dome(paw, (3.6, 4.4), 0.0, 0.15 + raise_by, 0.6 + raise_by)
    for angle in WOLF_TOES:
        direction = rotate((0.0, -1.0), math.radians(angle))
        layer.disk((paw[0] + direction[0] * 3.4, paw[1] + direction[1] * 3.6), 1.4, 0.5 + raise_by)
        layer.disk((paw[0] + direction[0] * 5.0, paw[1] + direction[1] * 5.2), 0.55, 0.06)


def wolf_leg(layer: Layer, index: int, side: float, t: float, flex: Callable[[float], float]) -> None:
    joint_r, rest_r = WOLF_LEGS[index]
    joint = mirror(joint_r, side)
    joint = (joint[0] + flex(joint[1]), joint[1])
    paw, lift = foot_at(joint, mirror(rest_r, side), leg_phase(index, side, t), WOLF_STRIDE, WOLF_PULL)
    bend = lerp(joint, paw, 0.5)
    # Přední noha má loket venku, zadní hlezno vzadu.
    bend = (bend[0] + side * 1.0, bend[1] + 4.0) if index else (bend[0] + side * 1.5, bend[1])
    high = 0.45 + 0.25 * lift
    layer.tube(line(joint, bend, 4), [5.0, 4.6, 4.2, 3.9], 0.12, high)
    layer.tube(line(bend, paw, 4), [3.9, 3.6, 3.3, 3.0], 0.12, high)
    paint_paw(layer, paw, lift)


def wolf_tail(layer: Layer, t: float, base_x: float) -> None:
    dense = profile(WOLF_TAIL)
    first_y = WOLF_TAIL[0][0]
    length = WOLF_TAIL[-1][0] - first_y
    spine = []
    for y, _w in dense:
        s = (y - first_y) / length
        spine.append((base_x + WOLF_TAIL_WAVE * s**1.3 * math.sin(math.tau * t - 1.2 * math.pi * s), y))
    widths = [w for _y, w in dense]
    tip = round((len(spine) - 1) * WOLF_TAIL_TIP)
    last = len(spine) - 1
    fringe(layer, spine, widths, 0, tip, 14, 2.0, 0.38, lean=0.9)
    fringe(layer, spine, widths, tip, last, 6, 2.0, 0.38, 0.8, lean=0.9)
    layer.tube(spine, widths, 0.2, 0.9)
    layer.tube(spine[tip:], widths[tip:], 0.2, 0.9, 0.8)


def wolf_head(layer: Layer, t: float, neck_x: float) -> None:
    yaw = math.radians(WOLF_HEAD_YAW) * math.sin(math.tau * t + math.pi / 2)

    def place(point: Point) -> Point:
        turned = rotate((point[0], point[1] - WOLF_NECK), yaw)
        return (neck_x + turned[0], WOLF_NECK + turned[1])

    dense = profile(WOLF_HEAD)
    spine = [place((0.0, y)) for y, _w in dense]
    widths = [w for _y, w in dense]
    fringe(layer, spine, widths, nearest(dense, -30.0), nearest(dense, -41.0), 5, 3.0, 0.4, 0.55, lean=0.8)
    layer.tube(spine, widths, 0.22, 0.95)
    start, end, radius, accent = WOLF_MUZZLE
    layer.capsule(place(start), place(end), radius, radius * 0.8, None, accent)
    for side in (-1.0, 1.0):
        start, end, radius, accent = WOLF_CHEEK
        layer.capsule(place(mirror(start, side)), place(mirror(end, side)), radius, radius * 0.8, None, accent)
        center, radius = WOLF_EYE
        layer.disk(place(mirror(center, side)), radius, None, 0.0, 1.0)
        ear = [place(mirror(point, side)) for point in WOLF_EAR]
        middle = ((ear[0][0] + ear[1][0] + ear[2][0]) / 3, (ear[0][1] + ear[1][1] + ear[2][1]) / 3)
        layer.polygon([lerp(middle, point, 1.3) for point in ear], 0.3)
        layer.polygon(ear, 0.92)
        layer.polygon([lerp(middle, point, 0.5) for point in ear], 0.66)
    layer.disk(place((0.0, -61.0)), 2.2, 0.06)


def wolf_layers(t: float) -> dict[int, Layer]:
    sway = WOLF_FLEX * math.sin(math.tau * t)

    def flex(y: float) -> float:
        return sway * -y / 30.0

    legs, body = Layer(WOLF_CANVAS), Layer(WOLF_CANVAS)
    for index in (1, 0):
        for side in (-1.0, 1.0):
            wolf_leg(legs, index, side, t, flex)

    wolf_tail(body, t, flex(WOLF_TAIL[0][0]))
    dense = profile(WOLF_BODY)
    spine = [(flex(y), y) for y, _w in dense]
    widths = [w for _y, w in dense]
    fringe(body, spine, widths, nearest(dense, -31.0), nearest(dense, -11.0), 10, 3.4, 0.4, 0.45)
    fringe(body, spine, widths, nearest(dense, -9.0), nearest(dense, 24.0), 12, 1.4, 0.36)
    body.tube(spine, widths, 0.2, 1.0)
    first, last = (nearest(dense, y) for y in WOLF_SADDLE_Y)
    saddle = spine[first : last + 1]
    for ratio, dim in WOLF_SADDLE:
        saddle_w = [w * ratio for w in widths[first : last + 1]]
        body.tube(saddle, saddle_w, 0.2 * dim, dim, depth=ratio)
    wolf_head(body, t, flex(WOLF_NECK))
    return {1: legs, 2: body}


def stone_band(
    layer: Layer,
    spine: list[Point],
    widths: list[float],
    first_cell: int,
    light: Callable[[int, float], float],
    accent: Callable[[int], float] = lambda index: 0.0,
    spark: float = SPARK_BODY,
) -> None:
    """Část těla podél páteře jako řady kamenů na tmavém jádru. Široké místo má víc kamenů vedle sebe.

    Řady sedí na pevných indexech páteře, takže se kameny s tělem jen posouvají. light dostane
    index páteře a vzdálenost od ní (díl šířky), accent index páteře.
    """
    layer.tube(spine, [w * 0.85 for w in widths], 0.04, 0.16)
    normals = spine_normals(spine)
    stones = []
    index, row = 0, 0
    while index < len(spine):
        width = widths[index]
        count = 1 if width < BAND_STONE_ACROSS[0] else 2 if width < BAND_STONE_ACROSS[1] else 3
        # Každá druhá řada má o kámen míň, spáry se střídají jako ve zdivu.
        if row % 2 and count > 1:
            count -= 1
        radius = max(1.2, width / max(count, 1.6) * BAND_STONE_SIZE)
        a = spine[max(0, index - 1)]
        b = spine[min(len(spine) - 1, index + 1)]
        angle = math.atan2(b[1] - a[1], b[0] - a[0])
        (px, py), (nx, ny) = spine[index], normals[index]
        tx, ty = -ny, nx
        for k in range(count):
            cell = first_cell + row * 3 + k
            across = 0.0 if count == 1 else (k / (count - 1) * 2.0 - 1.0) * BAND_STONE_SPREAD[count]
            across += BAND_STONE_JITTER * (facet_factor(cell, 60) - 0.5)
            along = radius * BAND_STONE_JITTER * (facet_factor(cell, 61) - 0.5)
            center = (px + nx * width * across + tx * along, py + ny * width * across + ty * along)
            size = radius * (0.85 + 0.25 * facet_factor(cell, 62))
            stones.append((abs(across), row, center, size, angle, cell, index, across))
        step = max(1, round(radius * BAND_STONE_STEP / max(0.1, math.dist(a, b) / 2.0)))
        index += step
        row += 1
    # Kraje první, hřbet navrch. Vzadu první, přední kámen leží na zadním.
    for _across, _row, center, radius, angle, cell, at, across in sorted(stones, key=lambda item: (-item[0], -item[1])):
        paint_stone(layer, center, radius, angle, cell, light(at, across), spark, BAND_STONE_STRETCH, accent(at))


def stone_wolf_leg(layer: Layer, index: int, side: float, t: float, flex: Callable[[float], float]) -> None:
    joint_r, rest_r = WOLF_LEGS[index]
    joint = mirror(joint_r, side)
    joint = (joint[0] + flex(joint[1]), joint[1])
    paw, lift = foot_at(joint, mirror(rest_r, side), leg_phase(index, side, t), WOLF_STRIDE, WOLF_PULL)
    bend = lerp(joint, paw, 0.5)
    bend = (bend[0] + side * 1.0, bend[1] + 4.0) if index else (bend[0] + side * 1.5, bend[1])
    cell = 1000 + index * 2 + (1 if side > 0 else 0)
    z = 9.0 + 9.0 * lift
    stone_segment(layer, joint, bend, z + 6.0, z + 3.0, 5.0, 4.2, WOLF_LEG_STONES, cell)
    stone_segment(layer, bend, paw, z + 3.0, z, 3.9, 3.2, WOLF_LEG_STONES, cell + 10)
    raise_by = 0.25 * lift
    paint_stone(layer, paw, 3.8, 0.0, 1100 + cell, 0.7 + raise_by, SPARK_LEG)
    for toe, angle in enumerate(WOLF_TOES):
        direction = rotate((0.0, -1.0), math.radians(angle))
        spot = (paw[0] + direction[0] * 4.4, paw[1] + direction[1] * 4.6)
        paint_stone(layer, spot, 1.5, math.radians(angle), 1200 + cell * 4 + toe, 0.8 + raise_by)


def stone_wolf_tail(layer: Layer, t: float, base_x: float) -> None:
    dense = profile(WOLF_TAIL)
    first_y = WOLF_TAIL[0][0]
    length = WOLF_TAIL[-1][0] - first_y
    spine = []
    for y, _w in dense:
        u = (y - first_y) / length
        spine.append((base_x + WOLF_TAIL_WAVE * u**1.3 * math.sin(math.tau * t - 1.2 * math.pi * u), y))
    widths = [w for _y, w in dense]
    tip = round((len(spine) - 1) * WOLF_TAIL_TIP)
    last = len(spine) - 1
    fringe(layer, spine, widths, 0, tip, 14, 2.0, 0.38, lean=0.9)
    fringe(layer, spine, widths, tip, last, 6, 2.0, 0.38, 0.8, lean=0.9)
    stone_band(
        layer, spine, widths, 1300,
        lambda at, across: 0.8 - 0.25 * abs(across),
        lambda at: 0.8 if at >= tip else 0.0,
    )


def stone_wolf_head(layer: Layer, t: float, neck_x: float) -> None:
    yaw = math.radians(WOLF_HEAD_YAW) * math.sin(math.tau * t + math.pi / 2)

    def place(point: Point) -> Point:
        turned = rotate((point[0], point[1] - WOLF_NECK), yaw)
        return (neck_x + turned[0], WOLF_NECK + turned[1])

    dense = profile(WOLF_HEAD)
    spine = [place((0.0, y)) for y, _w in dense]
    widths = [w for _y, w in dense]
    fringe(layer, spine, widths, nearest(dense, -30.0), nearest(dense, -41.0), 5, 3.0, 0.4, 0.55, lean=0.8)
    layer.tube(spine, [w * 0.85 for w in widths], 0.04, 0.16)
    for index, (center, radius, accent) in enumerate(WOLF_HEAD_STONES):
        for side in ((1.0,) if center[0] == 0.0 else (-1.0, 1.0)):
            spot = place(mirror(center, side))
            light = 0.95 - 0.004 * index
            paint_stone(layer, spot, radius, -math.pi / 2 + yaw, 1400 + index * 2 + (1 if side > 0 else 0), light, SPARK_BODY, 1.15, accent)
    for side in (-1.0, 1.0):
        center, radius = WOLF_EYE
        layer.disk(place(mirror(center, side)), radius + 0.4, 0.06)
        layer.disk(place(mirror(center, side)), radius, None, 0.0, 1.0)
        ear = [place(mirror(point, side)) for point in WOLF_EAR]
        middle = ((ear[0][0] + ear[1][0] + ear[2][0]) / 3, (ear[0][1] + ear[1][1] + ear[2][1]) / 3)
        layer.polygon([lerp(middle, point, 1.3) for point in ear], 0.3)
        layer.polygon(ear, 0.92)
        layer.polygon([lerp(middle, point, 0.5) for point in ear], 0.6)
    layer.disk(place((0.0, -61.0)), 2.2, 0.06)


def stone_wolf_layers(t: float) -> dict[int, Layer]:
    """Kamenný vlk: trup, ocas, hlava i nohy z kamenů, hřbet tmavší jako sedlo, svítí oči.

    Srst na obrysu zůstala jako ostré úlomky. Čenich, líce a špička ocasu jsou v akcentu.
    """
    sway = WOLF_FLEX * math.sin(math.tau * t)

    def flex(y: float) -> float:
        return sway * -y / 30.0

    legs, body = Layer(WOLF_CANVAS), Layer(WOLF_CANVAS)
    for index in (1, 0):
        for side in (-1.0, 1.0):
            stone_wolf_leg(legs, index, side, t, flex)

    stone_wolf_tail(body, t, flex(WOLF_TAIL[0][0]))
    dense = profile(WOLF_BODY)
    spine = [(flex(y), y) for y, _w in dense]
    widths = [w for _y, w in dense]
    fringe(body, spine, widths, nearest(dense, -31.0), nearest(dense, -11.0), 10, 3.4, 0.4, 0.45)
    fringe(body, spine, widths, nearest(dense, -9.0), nearest(dense, 24.0), 12, 1.4, 0.36)
    first, last = (nearest(dense, y) for y in WOLF_SADDLE_Y)

    def light(at: int, across: float) -> float:
        base = 0.62 + 0.38 * (1.0 - across * across)
        if first <= at <= last:
            base *= WOLF_STONE_SADDLE + (1.0 - WOLF_STONE_SADDLE) * min(1.0, abs(across) / 0.6)
        return base

    stone_band(body, spine, widths, 1500, light)
    stone_wolf_head(body, t, flex(WOLF_NECK))
    return {1: legs, 2: body}


def smooth(points: list[Point], per: int = 6) -> list[Point]:
    """Catmull-Rom přes body. Krajní body zůstanou."""
    out = []
    last = len(points) - 1
    for index in range(last):
        p0, p1 = points[max(index - 1, 0)], points[index]
        p2, p3 = points[index + 1], points[min(index + 2, last)]
        for k in range(per):
            s = k / per
            out.append(
                tuple(
                    0.5
                    * (
                        2.0 * p1[c]
                        + (p2[c] - p0[c]) * s
                        + (2.0 * p0[c] - 5.0 * p1[c] + 4.0 * p2[c] - p3[c]) * s * s
                        + (3.0 * p1[c] - p0[c] - 3.0 * p2[c] + p3[c]) * s * s * s
                    )
                    for c in (0, 1)
                )
            )
    out.append(points[-1])
    return out


def resample(points: list[Point], count: int) -> list[Point]:
    """Stejně vzdálené body po lomené čáře, od prvního po poslední."""
    lengths = [0.0]
    for a, b in zip(points, points[1:]):
        lengths.append(lengths[-1] + math.dist(a, b))
    total = lengths[-1] or 1.0
    out = []
    segment = 0
    for k in range(count):
        target = total * k / (count - 1)
        while segment < len(points) - 2 and lengths[segment + 1] < target:
            segment += 1
        span = (lengths[segment + 1] - lengths[segment]) or 1.0
        out.append(lerp(points[segment], points[segment + 1], (target - lengths[segment]) / span))
    return out


def ptero_wing(t: float) -> tuple[list[Point], list[Point], list[Point], float]:
    """Pravé křídlo: náběžná a odtoková hrana od trupu ke špičce, klouby a náklon.

    Náklon zkrátí rozpětí, jak ho vidí kamera shora. Při švihu nahoru se křídlo složí.
    """
    tilt = math.radians(PTERO_FLAP) * math.cos(math.tau * t)
    fold = PTERO_FOLD * max(0.0, -math.sin(math.tau * t))
    angles = [math.radians(spread + (folded - spread) * fold) for _length, spread, folded in PTERO_BONES]
    joints = [PTERO_SHOULDER]
    for (length, _spread, _folded), angle in zip(PTERO_BONES, angles):
        x, y = joints[-1]
        joints.append((x + length * math.cos(angle), y + length * math.sin(angle)))
    shoulder, elbow, wrist, tip = joints

    def behind(point: Point, angle: float, depth: float) -> Point:
        return (point[0] - math.sin(angle) * depth, point[1] + math.cos(angle) * depth)

    arm = math.atan2(wrist[1] - shoulder[1], wrist[0] - shoulder[0])
    lead = list(PTERO_ROOT) + [behind(lerp(shoulder, wrist, 0.5), arm, -PTERO_PROPATAGIUM), wrist, tip]
    trail = list(PTERO_TRAIL_ROOT) + [
        behind(elbow, (angles[0] + angles[1]) / 2, PTERO_TRAIL_ELBOW),
        behind(wrist, (angles[1] + angles[2]) / 2, PTERO_TRAIL_WRIST),
    ]
    trail += [behind(lerp(wrist, tip, along), angles[2], depth) for along, depth in PTERO_TRAIL]
    trail.append(tip)

    def flap(point: Point) -> Point:
        return (shoulder[0] + (point[0] - shoulder[0]) * math.cos(tilt), point[1])

    return [flap(point) for point in lead], [flap(point) for point in trail], [flap(point) for point in joints], tilt


def paint_ptero_wing(layer: Layer, t: float, side: float) -> None:
    lead, trail, joints, tilt = ptero_wing(t)
    lead = [mirror(point, side) for point in resample(smooth(lead), PTERO_SAMPLES)]
    trail = [mirror(point, side) for point in resample(smooth(trail), PTERO_SAMPLES)]
    shoulder, elbow, wrist, tip = (mirror(point, side) for point in joints)
    # Vodorovné křídlo je nejsvětlejší, zvednuté o kousek světlejší než spuštěné.
    bright = 0.7 + 0.3 * math.cos(tilt) + 0.08 * math.sin(tilt)
    for band in range(TUBE_BANDS):
        reach = 1.0 - band / TUBE_BANDS
        mid = 1.0 - (band + 0.5) / TUBE_BANDS
        edge = [lerp(a, b, reach) for a, b in zip(lead, trail)]
        layer.polygon(lead + edge[::-1], (0.46 + 0.4 * (1.0 - mid) ** 0.7) * bright)
    last = len(lead) - 1
    start, steps, weight = PTERO_TIP
    for step in range(steps):
        first = round((start + (1.0 - start) * step / steps) * last)
        layer.polygon(lead[first:] + trail[first:][::-1], None, weight * (step + 1) / steps)
    # Shora kryjí kosti svaly, náběžná hrana je jen oblý val bez tmavého obrysu.
    high = 0.95 * bright
    low = 0.55 * bright
    layer.tube(line(shoulder, elbow, 3), [3.6, 3.0, 2.7], low, high)
    layer.tube(line(elbow, wrist, 3), [2.7, 2.4, 2.2], low, high)
    layer.tube(line(wrist, tip, 6), [2.2, 1.9, 1.6, 1.3, 1.0, 0.7], low, high)
    for spread in (-10.0, 10.0, 30.0):
        direction = rotate((0.0, -1.0), math.radians(side * spread))
        claw = (wrist[0] + direction[0] * 4.0, wrist[1] + direction[1] * 4.0)
        layer.capsule(wrist, claw, 0.9, 0.5, 0.4)
        layer.disk(claw, 0.55, 0.06)


def paint_ptero_leg(layer: Layer, side: float, t: float) -> None:
    hip, knee, foot = (mirror(point, side) for point in PTERO_LEG)
    foot = (foot[0], foot[1] + 0.8 * math.sin(math.tau * t))
    layer.tube(line(hip, knee, 3), [1.9, 1.7, 1.5], 0.15, 0.5)
    layer.tube(line(knee, foot, 3), [1.5, 1.3, 1.1], 0.15, 0.5)
    for spread in (-15.0, 0.0, 15.0):
        direction = rotate((0.0, 1.0), math.radians(side * spread))
        layer.capsule(foot, (foot[0] + direction[0] * 2.6, foot[1] + direction[1] * 2.6), 0.6, 0.35, 0.08)


def ptero_head(layer: Layer, t: float) -> None:
    yaw = math.radians(PTERO_HEAD_YAW) * math.sin(math.tau * t)
    pivot = PTERO_NECK[-1][0]

    def place(point: Point) -> Point:
        turned = rotate((point[0], point[1] - pivot), yaw)
        return (turned[0], pivot + turned[1])

    dense = profile(PTERO_HEAD)
    layer.tube([place((0.0, y)) for y, _w in dense], [w for _y, w in dense], 0.22, 0.95)
    center, radius = PTERO_EYE
    for side in (-1.0, 1.0):
        eye = place(mirror(center, side))
        layer.disk(eye, radius + PTERO_EYE_RIM, 0.1)
        layer.disk(eye, radius, None, 0.0, 1.0)


def ptero_layers(t: float) -> dict[int, Layer]:
    body = Layer(PTERO_CANVAS)
    for side in (-1.0, 1.0):
        paint_ptero_leg(body, side, t)
    for side in (-1.0, 1.0):
        paint_ptero_wing(body, t, side)
    neck = profile(PTERO_NECK)
    body.tube([(0.0, y) for y, _w in neck], [w for _y, w in neck], 0.22, 0.9)
    dense = profile(PTERO_BODY)
    spine = [(0.0, y) for y, _w in dense]
    widths = [w for _y, w in dense]
    fringe(body, spine, widths, 0, len(spine) - 1, 10, 1.3, 0.35)
    body.tube(spine, widths, 0.22, 0.95)
    center, radii = PTERO_SHOULDER_DOME
    for side in (-1.0, 1.0):
        body.dome(mirror(center, side), radii, 0.0, 0.4, 0.95)
    first, last = (nearest(dense, y) for y in PTERO_SADDLE_Y)
    saddle = spine[first : last + 1]
    for ratio, dim in PTERO_SADDLE:
        body.tube(saddle, [w * ratio for w in widths[first : last + 1]], 0.22 * dim, 0.95 * dim, depth=ratio)
    ptero_head(body, t)
    return {1: body.shadow(), 2: body}


def ptero_edges(t: float, side: float) -> tuple[list[Point], list[Point], list[Point], float]:
    """Náběžná a odtoková hrana křídla po PTERO_SAMPLES bodech, klouby a náklon."""
    lead, trail, joints, tilt = ptero_wing(t)
    lead = [mirror(point, side) for point in resample(smooth(lead), PTERO_SAMPLES)]
    trail = [mirror(point, side) for point in resample(smooth(trail), PTERO_SAMPLES)]
    return lead, trail, [mirror(point, side) for point in joints], tilt


def ptero_wing_stones() -> tuple[tuple[int, float, float, int], ...]:
    """Kameny blány: (index podél rozpětí, díl cesty od náběžné k odtokové hraně, poloměr, číslo).

    Rozložení se spočítá z roztaženého křídla a pak už se nemění, kameny s blánou jen
    jedou a nepřeskakují. Kolik jich je vedle sebe, určí hloubka blány v místě.
    """
    lead, trail, _joints, _tilt = ptero_edges(PTERO_GLIDE_FRAME / PTERO_FRAMES, 1.0)
    stones = []
    index, row = 1, 0
    while index < PTERO_SAMPLES - 1:
        chord = math.dist(lead[index], trail[index])
        count = max(1, round(chord / (2.0 * PTERO_WING_STONE)))
        radius = max(PTERO_WING_STONE_MIN, chord / count * 0.5 * BAND_STONE_SIZE * 1.15)
        for k in range(count):
            cell = 3000 + row * 8 + k
            v = (k + 0.5 + BAND_STONE_JITTER * (facet_factor(cell, 60) - 0.5)) / count
            stones.append((index, v, radius * (0.85 + 0.25 * facet_factor(cell, 62)), cell))
        span = math.dist(lead[index], lead[min(index + 1, PTERO_SAMPLES - 1)]) or 1.0
        index += max(1, round(radius * BAND_STONE_STEP / span))
        row += 1
    return tuple(stones)


def stone_ptero_wing(layer: Layer, t: float, side: float) -> None:
    lead, trail, joints, tilt = ptero_edges(t, side)
    shoulder, elbow, wrist, tip = joints
    bright = 0.7 + 0.3 * math.cos(tilt) + 0.08 * math.sin(tilt)
    # Tmavá blána pod kameny prosvítá spárami.
    layer.polygon(lead + trail[::-1], 0.06)
    last = len(lead) - 1
    start, _steps, weight = PTERO_TIP
    cell_side = 0 if side > 0 else 500
    for index, v, radius, cell in PTERO_WING_STONES:
        a, b = lead[index], trail[index]
        nxt = min(index + 1, last)
        angle = math.atan2(lead[nxt][1] - a[1], lead[nxt][0] - a[0])
        along = index / last
        accent = weight * min(1.0, max(0.0, (along - start) / (1.0 - start)) * 1.6) if along >= start else 0.0
        light = bright * (0.95 - 0.35 * v)
        paint_stone(layer, lerp(a, b, v), radius, angle, cell + cell_side, light, SPARK_BODY, 1.2, accent)
    stone_segment(layer, shoulder, elbow, 30.0, 30.0, 3.6, 2.9, PTERO_BONE_STONES, 3500 + cell_side)
    stone_segment(layer, elbow, wrist, 30.0, 30.0, 2.9, 2.4, PTERO_BONE_STONES, 3510 + cell_side)
    stone_segment(layer, wrist, tip, 30.0, 26.0, 2.4, 1.0, PTERO_FINGER_STONES, 3520 + cell_side)
    for spread in (-10.0, 10.0, 30.0):
        direction = rotate((0.0, -1.0), math.radians(side * spread))
        claw = (wrist[0] + direction[0] * 4.0, wrist[1] + direction[1] * 4.0)
        layer.capsule(wrist, claw, 0.9, 0.5, 0.4)
        layer.disk(claw, 0.55, 0.06)


def stone_ptero_head(layer: Layer, t: float) -> None:
    yaw = math.radians(PTERO_HEAD_YAW) * math.sin(math.tau * t)
    pivot = PTERO_NECK[-1][0]

    def place(point: Point) -> Point:
        turned = rotate((point[0], point[1] - pivot), yaw)
        return (turned[0], pivot + turned[1])

    dense = profile(PTERO_HEAD)
    layer.tube([place((0.0, y)) for y, _w in dense], [w * 0.85 for _y, w in dense], 0.04, 0.16)
    for index, (y, radius) in enumerate(PTERO_HEAD_STONES):
        paint_stone(layer, place((0.0, y)), radius, -math.pi / 2 + yaw, 3600 + index, 0.95, SPARK_BODY, 1.3)
    center, radius = PTERO_EYE
    for side in (-1.0, 1.0):
        eye = place(mirror(center, side))
        layer.disk(eye, radius + PTERO_EYE_RIM, 0.06)
        layer.disk(eye, radius, None, 0.0, 1.0)


def stone_ptero_layers(t: float) -> dict[int, Layer]:
    """Kamenný ptakoještěr: blána poskládaná z plochých kamenů, kosti křídla, trup a hlava z kamenů."""
    body = Layer(PTERO_CANVAS)
    for side in (-1.0, 1.0):
        hip, knee, foot = (mirror(point, side) for point in PTERO_LEG)
        foot = (foot[0], foot[1] + 0.8 * math.sin(math.tau * t))
        for spread in (-15.0, 0.0, 15.0):
            direction = rotate((0.0, 1.0), math.radians(side * spread))
            body.capsule(foot, (foot[0] + direction[0] * 2.6, foot[1] + direction[1] * 2.6), 0.6, 0.35, 0.08)
        stone_segment(body, hip, knee, 20.0, 20.0, 1.9, 1.6, PTERO_BONE_STONES, 3700 + (1 if side > 0 else 0))
        stone_segment(body, knee, foot, 20.0, 16.0, 1.6, 1.2, PTERO_BONE_STONES, 3710 + (1 if side > 0 else 0))
    for side in (-1.0, 1.0):
        stone_ptero_wing(body, t, side)
    neck = profile(PTERO_NECK)
    stone_band(body, [(0.0, y) for y, _w in neck], [w for _y, w in neck], 3800, lambda at, across: 0.85)
    dense = profile(PTERO_BODY)
    spine = [(0.0, y) for y, _w in dense]
    widths = [w for _y, w in dense]
    fringe(body, spine, widths, 0, len(spine) - 1, 10, 1.3, 0.35)
    first, last = (nearest(dense, y) for y in PTERO_SADDLE_Y)

    def light(at: int, across: float) -> float:
        base = 0.62 + 0.38 * (1.0 - across * across)
        if first <= at <= last:
            base *= WOLF_STONE_SADDLE + (1.0 - WOLF_STONE_SADDLE) * min(1.0, abs(across) / 0.6)
        return base

    stone_band(body, spine, widths, 3900, light)
    center, _radii = PTERO_SHOULDER_DOME
    for side in (-1.0, 1.0):
        paint_stone(body, mirror(center, side), 4.6, 0.0, 3950 + (1 if side > 0 else 0), 0.95, SPARK_BODY)
    stone_ptero_head(body, t)
    return {1: body.shadow(), 2: body}


def rex_spine_x(y: float, t: float, hips: float) -> float:
    if y < REX_NECK_FROM:
        bend = min(1.0, (REX_NECK_FROM - y) / (REX_NECK_FROM - REX_NECK))
        return hips * (1.0 - 1.6 * bend)
    if y > REX_TAIL_FROM:
        s = min(1.0, (y - REX_TAIL_FROM) / REX_TAIL_LENGTH)
        return hips * (1.0 - s) + REX_TAIL_WAVE * s**1.5 * math.sin(math.tau * t - 1.6 * math.pi * s)
    return hips


def rex_leg(side: float, t: float, hips: float) -> tuple[Point, Point, Point, float]:
    """Kyčel, koleno pod stehnem, pata a zvednutí chodidla. Levá noha je na zemi v první polovině."""
    phase = (t + (0.0 if side < 0 else 0.5)) % 1.0
    hip = (side * REX_HIP[0] + hips, REX_HIP[1])
    foot, lift = foot_at(hip, mirror(REX_FOOT, side), phase, REX_STRIDE, REX_PULL)
    knee = lerp(hip, foot, 0.4)
    return hip, (knee[0] + side * 4.0, knee[1]), foot, lift


def paint_rex_foot(layer: Layer, heel: Point, side: float, lift: float) -> None:
    pad = (heel[0], heel[1] - 3.0)
    curl = 1.0 - 0.3 * lift
    raise_by = 0.25 * lift
    for angle, length in REX_TOES:
        heading = math.radians(side * (angle + REX_TOE_OUT))
        direction = rotate((0.0, -1.0), heading)
        tip = (pad[0] + direction[0] * length * curl, pad[1] + direction[1] * length * curl)
        layer.tube(line(pad, tip, 4), [4.2, 3.6, 3.0, 2.5], 0.14 + raise_by, 0.62 + raise_by)
        claw = (tip[0] + direction[0] * 4.5, tip[1] + direction[1] * 4.5)
        layer.capsule(tip, claw, 1.6, 0.6, 0.06)
    layer.dome(pad, (7.5, 8.5), 0.0, 0.16 + raise_by, 0.66 + raise_by)


def rex_head(layer: Layer, t: float, hips: float) -> None:
    yaw = math.radians(REX_HEAD_YAW) * math.sin(math.tau * t)
    neck = (rex_spine_x(REX_NECK, t, hips), REX_NECK)

    def place(point: Point) -> Point:
        turned = rotate((point[0], point[1] - REX_NECK), yaw)
        return (neck[0] + turned[0], neck[1] + turned[1])

    dense = profile(REX_HEAD)
    layer.tube([place((0.0, y)) for y, _w in dense], [w for _y, w in dense], 0.22, 0.95)
    for side in (-1.0, 1.0):
        horn_from, horn_to = (mirror(point, side) for point in REX_HORN)
        layer.capsule(place(horn_from), place(horn_to), 1.3, 0.8, None, 0.9)
        center, radius = REX_EYE
        layer.disk(place(mirror(center, side)), radius, None, 0.0, 1.0)
        center, radius = REX_NOSTRIL
        layer.disk(place(mirror(center, side)), radius, 0.12)


def rex_stripes(layer: Layer, spine: list[Point], widths: list[float]) -> None:
    normals = spine_normals(spine)
    ys = [point[1] for point in spine]

    def sample(y: float) -> tuple[Point, Point, float]:
        index = min(range(len(ys)), key=lambda k: abs(ys[k] - y))
        return spine[index], normals[index], widths[index]

    for y in REX_STRIPES:
        front, _n, _w = sample(y - 2.4)
        back, _n, _w = sample(y + 2.4)
        point, normal, width = sample(y + REX_STRIPE_LAG)
        reach = width * 0.82
        left = (point[0] + normal[0] * reach, point[1] + normal[1] * reach)
        right = (point[0] - normal[0] * reach, point[1] - normal[1] * reach)
        layer.polygon([front, left, back, right], None, 0.7)


def rex_arm(layer: Layer, side: float, t: float, hips: float) -> None:
    """Ruka roste z podbřišku. Kreslí se před trupem, ten zakryje rameno a ve stínu je celá."""
    swing = 1.2 * math.sin(math.tau * t + (0.0 if side > 0 else math.pi))
    shoulder, elbow, hand = (mirror(point, side) for point in REX_ARM)
    shift = rex_spine_x(shoulder[1], t, hips)
    shoulder = (shoulder[0] + shift, shoulder[1])
    elbow = (elbow[0] + shift, elbow[1] + swing * 0.5)
    hand = (hand[0] + shift, hand[1] + swing)
    layer.tube(line(shoulder, elbow, 3), [3.6, 3.3, 3.0], 0.15, 0.6)
    layer.tube(line(elbow, hand, 3), [3.0, 2.6, 2.3], 0.15, 0.6)
    for spread in (-12.0, 12.0):
        direction = rotate((0.0, -1.0), math.radians(side * spread))
        layer.capsule(hand, (hand[0] + direction[0] * 3.2, hand[1] + direction[1] * 3.2), 0.9, 0.4, 0.08)


def rex_layers(t: float) -> dict[int, Layer]:
    hips = -REX_SWAY * math.sin(math.tau * t)
    legs, body = Layer(REX_CANVAS), Layer(REX_CANVAS)

    for side in (-1.0, 1.0):
        hip, knee, heel, lift = rex_leg(side, t, hips)
        legs.tube(line(hip, knee), [10.0, 9.5, 9.0, 8.5, 8.0, 7.5], 0.15, 0.7)
        legs.tube(line(knee, heel), [7.0, 6.6, 6.2, 5.8, 5.4, 5.0], 0.12, 0.5 + 0.25 * lift)
        paint_rex_foot(legs, heel, side, lift)
        thigh = lerp(hip, heel, 0.32)
        body.tube(line(hip, (thigh[0] + side * 5.0, thigh[1])), [13.0, 12.3, 11.6, 10.9, 10.2, 9.5], 0.2, 0.82)
        rex_arm(body, side, t, hips)

    dense = profile(REX_BODY)
    spine = [(rex_spine_x(y, t, hips), y) for y, _w in dense]
    widths = [w for _y, w in dense]
    body.tube(spine, widths, 0.2, 1.0)
    rex_stripes(body, spine, widths)
    rex_head(body, t, hips)
    return {1: legs, 2: body}


def stone_rex_foot(layer: Layer, heel: Point, side: float, lift: float, cell: int) -> None:
    pad = (heel[0], heel[1] - 3.0)
    curl = 1.0 - 0.3 * lift
    raise_by = 0.25 * lift
    for toe, (angle, length) in enumerate(REX_TOES):
        heading = math.radians(side * (angle + REX_TOE_OUT))
        direction = rotate((0.0, -1.0), heading)
        tip = (pad[0] + direction[0] * length * curl, pad[1] + direction[1] * length * curl)
        claw = (tip[0] + direction[0] * 4.5, tip[1] + direction[1] * 4.5)
        layer.capsule(tip, claw, 1.6, 0.6, 0.06)
        stone_segment(layer, pad, tip, 6.0 + 8.0 * lift, 3.0 + 8.0 * lift, 4.2, 2.6, REX_TOE_STONES, cell * 4 + toe)
    paint_stone(layer, pad, 7.0, 0.0, 2000 + cell, 0.7 + raise_by, SPARK_LEG)


def stone_rex_head(layer: Layer, t: float, hips: float) -> None:
    yaw = math.radians(REX_HEAD_YAW) * math.sin(math.tau * t)
    neck = (rex_spine_x(REX_NECK, t, hips), REX_NECK)

    def place(point: Point) -> Point:
        turned = rotate((point[0], point[1] - REX_NECK), yaw)
        return (neck[0] + turned[0], neck[1] + turned[1])

    dense = profile(REX_HEAD)
    layer.tube([place((0.0, y)) for y, _w in dense], [w * 0.85 for _y, w in dense], 0.04, 0.16)
    for index, (center, radius) in enumerate(REX_HEAD_STONES):
        for side in ((1.0,) if center[0] == 0.0 else (-1.0, 1.0)):
            spot = place(mirror(center, side))
            cell = 2100 + index * 2 + (1 if side > 0 else 0)
            paint_stone(layer, spot, radius, -math.pi / 2 + yaw, cell, 0.95 - 0.03 * abs(center[0]) / 10.0, SPARK_BODY, 1.15)
    for side in (-1.0, 1.0):
        horn_from, horn_to = (mirror(point, side) for point in REX_HORN)
        layer.capsule(place(horn_from), place(horn_to), 1.3, 0.8, None, 0.9)
        center, radius = REX_EYE
        layer.disk(place(mirror(center, side)), radius + 0.5, 0.06)
        layer.disk(place(mirror(center, side)), radius, None, 0.0, 1.0)
        center, radius = REX_NOSTRIL
        layer.disk(place(mirror(center, side)), radius, 0.06)


def stone_rex_arm(layer: Layer, side: float, t: float, hips: float) -> None:
    swing = 1.2 * math.sin(math.tau * t + (0.0 if side > 0 else math.pi))
    shoulder, elbow, hand = (mirror(point, side) for point in REX_ARM)
    shift = rex_spine_x(shoulder[1], t, hips)
    shoulder = (shoulder[0] + shift, shoulder[1])
    elbow = (elbow[0] + shift, elbow[1] + swing * 0.5)
    hand = (hand[0] + shift, hand[1] + swing)
    cell = 2200 + (1 if side > 0 else 0)
    for spread in (-12.0, 12.0):
        direction = rotate((0.0, -1.0), math.radians(side * spread))
        layer.capsule(hand, (hand[0] + direction[0] * 3.2, hand[1] + direction[1] * 3.2), 0.9, 0.4, 0.08)
    stone_segment(layer, shoulder, elbow, 14.0, 14.0, 3.6, 3.3, REX_ARM_STONES, cell)
    stone_segment(layer, elbow, hand, 14.0, 12.0, 3.0, 2.4, REX_ARM_STONES, cell + 2)


def stone_rex_layers(t: float) -> dict[int, Layer]:
    """Kamenný tyranosaurus: trup, ocas, hlava i nohy z kamenů, pruhy vtlačené do kamenů."""
    hips = -REX_SWAY * math.sin(math.tau * t)
    legs, body = Layer(REX_CANVAS), Layer(REX_CANVAS)

    for side in (-1.0, 1.0):
        hip, knee, heel, lift = rex_leg(side, t, hips)
        cell = 2300 + (1 if side > 0 else 0) * 10
        z = 10.0 + 10.0 * lift
        stone_segment(legs, hip, knee, z + 14.0, z + 8.0, 10.0, 7.5, REX_LEG_STONES, cell)
        stone_segment(legs, knee, heel, z + 8.0, z, 7.0, 5.0, REX_LEG_STONES, cell + 1)
        stone_rex_foot(legs, heel, side, lift, cell + 2)
        thigh = lerp(hip, heel, 0.32)
        stone_segment(body, hip, (thigh[0] + side * 5.0, thigh[1]), 26.0, 24.0, 13.0, 9.5, REX_THIGH_STONES, cell + 3)
        stone_rex_arm(body, side, t, hips)

    dense = profile(REX_BODY)
    spine = [(rex_spine_x(y, t, hips), y) for y, _w in dense]
    widths = [w for _y, w in dense]
    stone_band(body, spine, widths, 2400, lambda at, across: 0.62 + 0.38 * (1.0 - across * across))
    rex_stripes(body, spine, widths)
    stone_rex_head(body, t, hips)
    return {1: legs, 2: body}


def snake_wave_x(y: float, t: float) -> float:
    """Vybočení páteře za krkem. Vlna je pevná vůči zemi, ve hře se nehýbe, had po ní klouže."""
    behind = y - (SNAKE_SNOUT + SNAKE_NECK)
    if behind <= 0.0:
        return 0.0
    u = min(1.0, behind / SNAKE_RAMP)
    grow = 0.7 + 0.3 * min(1.0, behind / 70.0)
    return SNAKE_AMPLITUDE * u * u * (3.0 - 2.0 * u) * grow * math.sin(math.tau * (y / SNAKE_WAVE - t))


def snake_spine(t: float) -> tuple[list[Point], list[float], list[float]]:
    """Páteř od čenichu po špičku ocasu, šířky a délka s každého bodu.

    Tělo za krkem leží na vlně a má pořád stejnou délku, takže se kresba nesmýká.
    """
    dense = profile(SNAKE_WIDTH, 0.5)
    neck_y = SNAKE_SNOUT + SNAKE_NECK
    step = 0.25
    trail = [(snake_wave_x(neck_y + k * step, t), neck_y + k * step) for k in range(round(2.0 * SNAKE_LENGTH / step))]
    lengths = [0.0]
    for a, b in zip(trail, trail[1:]):
        lengths.append(lengths[-1] + math.dist(a, b))
    yaw = math.radians(SNAKE_HEAD_YAW) * math.sin(math.tau * t)
    spine = []
    for s, _w in dense:
        if s <= SNAKE_NECK:
            turned = rotate((0.0, s - SNAKE_NECK), yaw)
            spine.append((trail[0][0] + turned[0], trail[0][1] + turned[1]))
            continue
        target = s - SNAKE_NECK
        index = min(bisect.bisect_left(lengths, target), len(lengths) - 1)
        span = (lengths[index] - lengths[index - 1]) or 1.0
        spine.append(lerp(trail[index - 1], trail[index], (target - lengths[index - 1]) / span))
    return spine, [w for _s, w in dense], [s for s, _w in dense]


class SnakeShape:
    """Had ve fázi t: páteř, šířky, délky s a body na hřbetě."""

    def __init__(self, t: float) -> None:
        self.spine, self.widths, self.lengths = snake_spine(t)
        self.normals = spine_normals(self.spine)

    def index_of(self, s: float) -> int:
        return min(bisect.bisect_left(self.lengths, s), len(self.lengths) - 1)

    def at(self, s: float, across: float) -> Point:
        """Bod na hřbetě: across je díl poloviční šířky od páteře, kladný vpravo."""
        index = self.index_of(s)
        (px, py), (nx, ny), width = self.spine[index], self.normals[index], self.widths[index]
        return (px - nx * width * across, py - ny * width * across)

    def angle(self, s: float) -> float:
        """Směr páteře v místě s, od čenichu k ocasu."""
        index = self.index_of(s)
        a = self.spine[max(0, index - 2)]
        b = self.spine[min(len(self.spine) - 1, index + 2)]
        return math.atan2(b[1] - a[1], b[0] - a[0])

    def diamond(self, layer: Layer, center: float, shrink: float, across: float, rim: float | None = 0.16) -> None:
        """Kosočtverec na hřbetě. rim None vynechá tmavý lem a nechá světlost pod kresbou."""
        _first, _last, _gap, half_length, _half_width = SNAKE_DIAMONDS
        corners = [
            self.at(center - half_length * shrink, 0.0),
            self.at(center, across),
            self.at(center + half_length * shrink, 0.0),
            self.at(center, -across),
        ]
        if rim is not None:
            for a, b in zip(corners, corners[1:] + corners[:1]):
                layer.capsule(a, b, SNAKE_RIM, SNAKE_RIM, rim)
        middle = self.at(center, 0.0)
        layer.polygon([lerp(middle, corner, 0.82) for corner in corners], None, 0.9)

    def markings(self, layer: Layer, rim: float | None = 0.16) -> None:
        """Kosočtverce na hřbetě a skvrny na bocích mezi nimi."""
        first, last, gap, _half_length, half_width = SNAKE_DIAMONDS
        spot_across, spot_radius, spot_accent = SNAKE_SPOTS
        center = first
        while center <= last + 0.01:
            shrink = min(1.0, self.widths[self.index_of(center)] / SNAKE_WIDE)
            self.diamond(layer, center, shrink, half_width, rim)
            for side in (-1.0, 1.0):
                layer.disk(self.at(center + gap / 2, side * spot_across), spot_radius * shrink, None, spot_accent)
            center += gap

    def tongue(self, layer: Layer, t: float) -> None:
        """Jazyk je pod hlavou, vyjede z tlamy a zase zajede. Dvakrát za cyklus."""
        out = max(0.0, math.sin(math.tau * 2.0 * t)) ** 0.6
        if out <= 0.05:
            return
        spine = self.spine
        reach, fork, spread = SNAKE_TONGUE
        tip = spine[0]
        dx, dy = tip[0] - spine[4][0], tip[1] - spine[4][1]
        norm = math.hypot(dx, dy) or 1.0
        forward = (dx / norm, dy / norm)
        split = (tip[0] + forward[0] * reach * out, tip[1] + forward[1] * reach * out)
        layer.capsule(spine[2], split, 0.45, 0.4, 0.3, 0.0, 1.0)
        for side in (-1.0, 1.0):
            prong = rotate(forward, math.radians(side * spread))
            end = (split[0] + prong[0] * fork * out, split[1] + prong[1] * fork * out)
            layer.capsule(split, end, 0.4, 0.25, 0.3, 0.0, 1.0)

    def eyes(self, layer: Layer) -> None:
        for side in (-1.0, 1.0):
            s, across, radius = SNAKE_EYE
            eye = self.at(s, side * across)
            layer.disk(eye, radius + 0.45, 0.1)
            layer.disk(eye, radius, None, 0.0, 1.0)
            s, across, radius = SNAKE_NOSTRIL
            layer.disk(self.at(s, side * across), radius, 0.08)


def snake_layers(t: float) -> dict[int, Layer]:
    shape = SnakeShape(t)
    spine, widths = shape.spine, shape.widths
    body, head = Layer(SNAKE_CANVAS), Layer(SNAKE_CANVAS)
    tuck, raise_ = shape.index_of(SNAKE_TUCK), shape.index_of(SNAKE_RAISE)
    body.tube(spine[tuck:], widths[tuck:], 0.2, 1.0)
    shape.markings(body)
    shape.tongue(head, t)
    head.tube(spine[: raise_ + 1], widths[: raise_ + 1], 0.24, 1.0)
    # Na temeni je menší kosočtverec, kresba těla tak začíná už na hlavě.
    shape.diamond(head, SNAKE_CROWN, 0.75, 0.42)
    shape.eyes(head)
    return {1: body, 2: head}


def stone_snake_layers(t: float) -> dict[int, Layer]:
    """Kamenný had: řada kamenů podél páteře na tmavém jádru, kresba vtlačená do kamenů.

    Kameny sedí na pevných místech s, takže s hadem klouzají a nepřeskakují.
    """
    shape = SnakeShape(t)
    spine, widths = shape.spine, shape.widths
    body, head = Layer(SNAKE_CANVAS), Layer(SNAKE_CANVAS)
    tuck, raise_ = shape.index_of(SNAKE_TUCK), shape.index_of(SNAKE_RAISE)
    body.tube(spine[tuck:], [w * 0.8 for w in widths[tuck:]], 0.04, 0.16)
    # Od ocasu k hlavě, přední kámen leží na zadním jako šupina.
    for index, (s, across, size) in reversed(list(enumerate(SNAKE_STONES))):
        width = widths[shape.index_of(s)]
        paint_stone(body, shape.at(s, across), width * size, shape.angle(s), 700 + index, 0.85, SPARK_BODY, SNAKE_STONE_STRETCH)
    shape.markings(body, None)
    shape.tongue(head, t)
    head.tube(spine[: raise_ + 1], [w * 0.8 for w in widths[: raise_ + 1]], 0.04, 0.16)
    for index, (s, size) in enumerate(SNAKE_HEAD_STONES):
        width = widths[shape.index_of(s)]
        paint_stone(head, shape.at(s, 0.0), width * size, shape.angle(s), 900 + index, 0.95, SPARK_BODY, SNAKE_STONE_STRETCH)
    shape.diamond(head, SNAKE_CROWN, 0.75, 0.42, None)
    shape.eyes(head)
    return {1: body, 2: head}


def snake_width(s: float) -> float:
    """Poloviční šířka hada v místě s, lineárně mezi body SNAKE_WIDTH."""
    for (s0, w0), (s1, w1) in zip(SNAKE_WIDTH, SNAKE_WIDTH[1:]):
        if s <= s1:
            return w0 + (w1 - w0) * max(0.0, (s - s0) / (s1 - s0))
    return SNAKE_WIDTH[-1][1]


def snake_stones() -> tuple[tuple[float, float, float], ...]:
    """Kameny těla: (s, díl šířky do strany, poloměr jako díl šířky). Rozestup roste se šířkou."""
    stones = []
    s = SNAKE_TUCK + 1.0
    side = 1.0
    while s < SNAKE_LENGTH - 1.5:
        width = snake_width(s)
        stones.append((s, side * SNAKE_STONE_SWAY, SNAKE_STONE_SIZE))
        s += max(SNAKE_STONE_STEP[0], width * SNAKE_STONE_STEP[1])
        side = -side
    return tuple(stones)


SNAKE_STONES = snake_stones()


PTERO_WING_STONES = ptero_wing_stones()


def ball_stones() -> tuple[tuple[float, float, float], ...]:
    """Body kamenů na kouli o poloměru 1 (Fibonacciho spirála s drobným posunem)."""
    golden = math.pi * (3.0 - math.sqrt(5.0))
    points = []
    for index in range(BALL_STONES):
        z = 1.0 - 2.0 * (index + 0.5) / BALL_STONES
        r = math.sqrt(1.0 - z * z)
        a = golden * index + 0.4 * (facet_factor(900 + index, 3) - 0.5)
        points.append((math.cos(a) * r, math.sin(a) * r, z))
    return tuple(points)


BALL_STONE_POINTS = ball_stones()


def unit(vector: tuple[float, float, float]) -> tuple[float, float, float]:
    length = math.sqrt(sum(value * value for value in vector)) or 1.0
    return (vector[0] / length, vector[1] / length, vector[2] / length)


BALL_FACE_DIR = unit(BALL_FACE)
BALL_FACE_COS = math.cos(math.radians(BALL_FACE_ANGLE))


def face_stones() -> tuple[tuple[float, float, float], ...]:
    """Kameny obličejové desky: hustší Fibonacciho spirála, jen body uvnitř čepičky a nad horizontem."""
    golden = math.pi * (3.0 - math.sqrt(5.0))
    points = []
    for index in range(BALL_FACE_DENSITY):
        z = 1.0 - 2.0 * (index + 0.5) / BALL_FACE_DENSITY
        r = math.sqrt(1.0 - z * z)
        a = golden * index + 0.4 * (facet_factor(1200 + index, 3) - 0.5)
        point = (math.cos(a) * r, math.sin(a) * r, z)
        if point[2] >= -BALL_HIDE and sum(p * f for p, f in zip(point, BALL_FACE_DIR)) > BALL_FACE_COS - 0.02:
            points.append(point)
    return tuple(points)


BALL_FACE_STONES = face_stones()


def ball_stone(layer: Layer, point: tuple[float, float, float], index: int, dim: float, shift: float = 0.0) -> None:
    """Kámen na kouli v bodě point (poloměr 1), posunutý o shift px dopředu. U horizontu se zploští
    ve směru od středu."""
    x, y, z = point
    radial = math.atan2(y, x) if abs(x) + abs(y) > 1e-6 else 0.0
    radius = BALL_STONE_R * (0.85 + 0.3 * facet_factor(index, 5))
    light = (BALL_LIGHT[0] + BALL_LIGHT[1] * max(0.0, z) ** 0.7) * dim
    paint_stone(layer, (x * BALL_R, y * BALL_R - shift), radius, radial, 700 + index, light, SPARK_BODY, max(0.35, z))


def face_outline() -> list[Point]:
    """Obrys obličejové desky na obrazovce. Část za horizontem se přitiskne na obrys koule."""
    fx, fy, fz = BALL_FACE_DIR
    side = (1.0, 0.0, 0.0)
    up = unit((fy * side[2] - fz * side[1], fz * side[0] - fx * side[2], fx * side[1] - fy * side[0]))
    spread = math.sin(math.radians(BALL_FACE_ANGLE))
    points = []
    for k in range(48):
        a = math.tau * k / 48
        x, y, z = (
            BALL_FACE_COS * f + spread * (math.cos(a) * e1 + math.sin(a) * e2)
            for f, e1, e2 in zip(BALL_FACE_DIR, side, up)
        )
        if z < 0.0:
            flat = math.hypot(x, y) or 1.0
            x, y = x / flat, y / flat
        points.append((x * BALL_R, y * BALL_R - BALL_FACE_SHIFT))
    return points


def paint_ball(layer: Layer, t: float, dim: float) -> None:
    """Koule z kamenů na tmavém jádru, otočená o fázi t dopředu. Vzdálenější kameny se kreslí dřív.

    Přes ni pevná obličejová deska: tmavá čepička a na ní kameny v poloze z fáze 0.
    """
    layer.dome((0.0, 0.0), (BALL_R * 0.97, BALL_R * 0.97), 0.0, 0.04, 0.16)
    c, s = math.cos(math.tau * t), math.sin(math.tau * t)
    placed = []
    for index, (x, y, z) in enumerate(BALL_STONE_POINTS):
        # Valí se na sever: vršek koule jede dopředu (-Y).
        turned = (x, y * c - z * s, y * s + z * c)
        if turned[2] >= -BALL_HIDE:
            placed.append((turned[2], turned, index))
    placed.sort()
    for _z, point, index in placed:
        ball_stone(layer, point, index, dim)
    ridge = Layer(layer.canvas)
    paint_ball_ridge(ridge, t, dim)
    layer.blend(ridge, ridge_mask(layer.canvas))
    plate = Layer(layer.canvas)
    plate.polygon(face_outline(), 0.04)
    for _z, point, index in sorted((point[2], point, index) for index, point in enumerate(BALL_FACE_STONES)):
        ball_stone(plate, point, 1000 + index, dim * BALL_FACE_LIGHT, BALL_FACE_SHIFT)
    layer.blend(plate, face_mask(layer.canvas))


def ridge_mask(canvas: int) -> Image.Image:
    """Krytí hřbetního pásu: vpředu plné, ke konci za středem koule plynule klesá k nule."""
    size = canvas * SS
    layer = Layer(canvas)
    _x, end = layer.px((0.0, BALL_RIDGE_END * BALL_R))
    fade = BALL_RIDGE_FADE * SS
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    for row in range(size):
        s = max(0.0, min(1.0, (end - row) / fade))
        draw.line((0, row, size, row), fill=byte(s * s * (3.0 - 2.0 * s)))
    return mask


def face_mask(canvas: int) -> Image.Image:
    """Krytí obličejové desky: uvnitř plné, k okraji na kouli plynule klesá k nule. Mimo kouli
    (kde deska přečnívá) je plné, takže tam okraj zůstane ostrý."""
    size = canvas * SS
    feather = BALL_FACE_FEATHER * SS
    inside = Image.new("L", (size, size), 0)
    layer = Layer(canvas)
    ImageDraw.Draw(inside).polygon([layer.px(point) for point in face_outline()], fill=255)
    # Okraj se nejdřív zúží o polovinu přechodu a pak rozmaže, takže na obrysu je krytí skoro nula.
    shrink = 2 * round(feather / 2) + 1
    mask = inside.filter(ImageFilter.MinFilter(shrink)).filter(ImageFilter.GaussianBlur(feather / 2))
    ball = Image.new("L", (size, size), 0)
    cx, cy = layer.px((0.0, 0.0))
    r = BALL_R * 0.96 * SS
    ImageDraw.Draw(ball).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    outside = ImageChops.invert(ball.filter(ImageFilter.GaussianBlur(SS)))
    return ImageChops.lighter(mask, outside)


def ridge_stones() -> tuple[tuple[float, float, float, float], ...]:
    """Kameny jednoho úseku hřebene: (díl úseku podél, vybočení, poloměr, světlost). Menší první,
    větší se kreslí přes ně."""
    stones = []
    for k in range(BALL_RIDGE_STONES):
        along = (k + 0.15 + 0.7 * facet_factor(1500 + k, 1)) / BALL_RIDGE_STONES
        across = BALL_RIDGE_ACROSS * (2.0 * facet_factor(1500 + k, 2) - 1.0)
        size = BALL_RIDGE_SIZE[0] + (BALL_RIDGE_SIZE[1] - BALL_RIDGE_SIZE[0]) * facet_factor(1500 + k, 3)
        # Kameny u osy jsou větší, ať pás tvoří hřeben.
        size *= 1.0 - 0.35 * abs(across) / BALL_RIDGE_ACROSS
        light = BALL_RIDGE_LIGHT[0] + (BALL_RIDGE_LIGHT[1] - BALL_RIDGE_LIGHT[0]) * facet_factor(1500 + k, 4)
        stones.append((along, across, size, light))
    return tuple(sorted(stones, key=lambda stone: stone[2]))


BALL_RIDGE = ridge_stones()


def paint_ball_ridge(layer: Layer, t: float, dim: float) -> None:
    """Hřbetní hřeben: tmavý pás se zvlněným okrajem přes vršek a na něm nepravidelně rozházené
    kameny. Valí se dopředu pomaleji než koule, přední konec zajede pod obličejovou desku.
    Kreslí se kolem celé koule, zadní část pak ořízne ridge_mask."""
    tiles = round(1.0 / BALL_RIDGE_SPEED)
    tile = math.tau / tiles
    # Za cyklus se pás posune o jeden úsek.
    roll = tile * t

    def on_ball(angle: float, across: float) -> tuple[float, float, float]:
        # Stejný směr jako koule: vršek jede dopředu (-Y).
        ring = math.sqrt(1.0 - across * across)
        return (across, -math.sin(angle) * ring, math.cos(angle) * ring)

    def width(angle: float) -> float:
        middle, wobble = BALL_RIDGE_WIDTH
        phase = (angle - roll) * tiles
        return middle + wobble * (0.6 * math.sin(phase) + 0.4 * math.sin(2.0 * phase + 1.3))

    angles = [-math.pi / 2 + math.pi * k / 40 for k in range(41)]
    right = [on_ball(angle, width(angle)) for angle in angles]
    left = [on_ball(angle, -width(angle)) for angle in reversed(angles)]
    layer.polygon([(x * BALL_R, y * BALL_R) for x, y, _z in right + left], 0.05)

    placed = []
    for repeat in range(tiles):
        for index, (along, across, size, light) in enumerate(BALL_RIDGE):
            point = on_ball(tile * (repeat + along) + roll, across)
            if point[2] >= -BALL_HIDE:
                placed.append((point[2], size, point, index, light))
    for _z, size, (x, y, z), index, light in sorted(placed):
        lit = (BALL_LIGHT[0] + BALL_LIGHT[1] * max(0.0, z) ** 0.7) * light * dim
        radial = math.atan2(y, x) if abs(x) + abs(y) > 1e-6 else 0.0
        # U horizontu se kámen zploští ve směru od středu.
        paint_stone(layer, (x * BALL_R, y * BALL_R), size, radial, 1400 + index, min(1.0, lit), SPARK_BODY, max(0.35, z))


def bite_open(t: float) -> float:
    """Jak moc je tlama otevřená ve fázi t, 0 až 1. Pomalu se otvírá, rychle cvakne."""
    phase = (t * BALL_BITES) % 1.0
    skew = phase ** (math.log(0.5) / math.log(BALL_BITE_PEAK))
    return math.sin(math.pi * skew) ** 1.5


def paint_ball_mouth(layer: Layer, t: float) -> None:
    """Zamračená tlama vpředu, která kouše: horní ret stojí, spodní čelist klesá dopředu.
    Uvnitř žhne, nahoře a dole kamenné zuby, zavřené se zaklesnou do sebe.

    Nahoru po tváři je k vršku koule (+Y), koutky klesají dopředu (-Y).
    """
    x, y, z = unit(BALL_MOUTH)
    cx, cy = x * BALL_R, y * BALL_R - BALL_FACE_SHIFT
    w, top = BALL_MOUTH_SIZE
    opened = bite_open(t)
    jaw = BALL_JAW[0] + (BALL_JAW[1] - BALL_JAW[0]) * opened

    def at(u: float, v: float) -> Point:
        return (cx + u, cy + v - BALL_MOUTH_FROWN * (u / w) ** 2)

    def outline(grow: float) -> list[Point]:
        # Horní půlka má výšku horního rtu, spodní výšku čelisti.
        points = []
        for k in range(32):
            q = math.tau * k / 32
            height = (top if math.sin(q) > 0.0 else jaw) + grow
            points.append(at((w + grow) * math.cos(q), height * math.sin(q)))
        return points

    layer.polygon(outline(1.0), 0.03)
    glow = BALL_MOUTH_GLOW[0] + (BALL_MOUTH_GLOW[1] - BALL_MOUTH_GLOW[0]) * opened
    layer.polygon(outline(0.0), 0.04, 0.0, glow)
    upper, lower, size = BALL_TEETH
    # Spodní zuby první, horní přes ně, ať se zavřené zaklesnou.
    for count, edge, height in ((lower, -1.0, jaw), (upper, 1.0, top)):
        span = 2.0 * w * 0.82 / count
        for k in range(count):
            u = -w * 0.82 + span * (k + 0.5)
            root = height * edge * math.sqrt(max(0.0, 1.0 - (u / w) ** 2))
            tip = root - edge * size * (0.75 + 0.25 * facet_factor(950 + k, int(edge + 2)))
            half = span * 0.42
            # Tmavý obrys oddělí zub od žáru i od souseda.
            layer.polygon([at(u - half - 0.6, root + edge * 0.8), at(u + half + 0.6, root + edge * 0.8), at(u, tip - edge * 0.7)], 0.03)
            layer.polygon([at(u - half, root + edge * 0.6), at(u + half, root + edge * 0.6), at(u, tip)], 1.0, BALL_TEETH_ACCENT)


def ball_layers(t: float) -> dict[int, Layer]:
    """Kamenná koule: spodní vrstva je tatáž koule tmavší, horní má navíc oči."""
    low, top = Layer(BALL_CANVAS), Layer(BALL_CANVAS)
    paint_ball(low, t, BALL_LOW_DIM)
    paint_ball(top, t, 1.0)
    for side in (-1.0, 1.0):
        paint_ball_eye(top, side)
    paint_ball_mouth(top, t)
    return {1: low, 2: top}


def paint_ball_eye(layer: Layer, side: float) -> None:
    """Zlověstné oko: šikmá svítící mandle v důlku, štěrbina zornice a zamračené kamenné obočí.

    Nahoru po tváři je k vršku koule (+Y), vnitřní koutek míří ke středu a dopředu.
    """
    x, y, z = BALL_EYE
    length = math.sqrt(x * x + y * y + z * z)
    center = (side * x / length * BALL_R, y / length * BALL_R - BALL_FACE_SHIFT)
    # Osa oka ven od nosu: ven a zároveň nahoru po tváři.
    tilt = math.radians(BALL_EYE_TILT)
    along = (side * math.cos(tilt), math.sin(tilt))
    up = (-along[1] * side, along[0] * side)

    def at(u: float, v: float) -> Point:
        return (center[0] + along[0] * u + up[0] * v, center[1] + along[1] * u + up[1] * v)

    def almond(grow: float) -> list[Point]:
        a, b = BALL_EYE_SIZE[0] + grow, BALL_EYE_SIZE[1] + grow
        # Mandle: špičaté koutky, víčka se zužují ke krajům.
        return [at(a * math.cos(q), b * math.sin(q) * abs(math.sin(q)) ** 0.35)
                for q in (math.tau * k / 24 for k in range(24))]

    a, b = BALL_EYE_SIZE
    inner, outer = (BALL_LID[0] * b, BALL_LID[1] * b)
    reach = a + BALL_SOCKET + 1.0
    layer.polygon(almond(BALL_SOCKET), 0.03)
    layer.polygon(almond(0.0), None, 0.0, 1.0)
    layer.capsule(at(0.6, -BALL_PUPIL[0]), at(0.6, BALL_PUPIL[0]), BALL_PUPIL[1], BALL_PUPIL[1], 0.02, 0.0, 0.0)
    # Víčko: všechno nad šikmou hranou je tmavý důlek.
    rise = (outer - inner) / (2.0 * a)
    edge = lambda u: inner + (u + a) * rise
    layer.polygon([at(-reach, edge(-reach)), at(reach, edge(reach)), at(reach, edge(reach) + 6.0), at(-reach, edge(-reach) + 6.0)], 0.03)
    lift, radius, stretch = BALL_BROW
    brow_angle = math.atan2(along[1] + up[1] * rise, along[0] + up[0] * rise)
    paint_stone(layer, at(0.0, edge(0.0) + lift), radius, brow_angle, 880 + (1 if side > 0 else 0), 0.62, 0.0, stretch)


# Kreslení druhu dostane fázi cyklu 0 až 1, ne číslo snímku.
RENDERERS: dict[str, Callable[[float], dict[int, Layer]]] = {
    "had": snake_layers,
    "had2": stone_snake_layers,
    "pavouk": spider_layers,
    "pavouk2": golem_layers,
    "vlk": wolf_layers,
    "vlk2": stone_wolf_layers,
    "ptakojester": ptero_layers,
    "ptakojester2": stone_ptero_layers,
    "tyranosaurus": rex_layers,
    "rex2": stone_rex_layers,
    "koule2": ball_layers,
}


def pack(layer: Layer, zoom: float = 1.0) -> Image.Image:
    """Zmenší masky. Světlost, akcent a oči jsou průměr zakrytých vzorků, alfa je krytí.

    zoom zmenší celý tvor, buňka zůstane sudá, aby střed zůstal ve středu plátna.
    """
    shade, accent, eye, alpha = layer.channels
    cell = 2 * round(layer.canvas * zoom / 2)
    size = (cell, cell)
    cover = alpha.convert("F").resize(size, Image.Resampling.BOX).load()
    sums = [
        ImageChops.multiply(channel, alpha).convert("F").resize(size, Image.Resampling.BOX).load()
        for channel in (shade, accent, eye)
    ]
    out = Image.new("RGBA", size)
    target = out.load()
    for y in range(cell):
        for x in range(cell):
            a = cover[x, y]
            if a <= 0.0:
                target[x, y] = (0, 0, 0, 0)
                continue
            r, g, b = (min(255, round(total[x, y] * 255.0 / a)) for total in sums)
            target[x, y] = (r, g, b, min(255, round(a)))
    return out


def pack_spark(layer: Layer, mask: Image.Image) -> Image.Image:
    """Semínka odlesků zmenšená jako ostatní masky: G je jas semínka, alfa je z masky vrstvy,
    aby se atlas ořízl stejně."""
    _shade, _accent, _eye, alpha = layer.channels
    size = mask.size
    cover = alpha.convert("F").resize(size, Image.Resampling.BOX).load()
    total = ImageChops.multiply(layer.spark, alpha).convert("F").resize(size, Image.Resampling.BOX).load()
    out = Image.new("RGBA", size)
    target = out.load()
    opaque = mask.getchannel("A").load()
    for y in range(size[1]):
        for x in range(size[0]):
            a = cover[x, y]
            g = 0 if a <= 0.0 else min(255, round(total[x, y] * 255.0 / a))
            target[x, y] = (0, g, 0, opaque[x, y])
    return out


def colorize(
    mask: Image.Image,
    body: tuple[int, int, int],
    accent: tuple[int, int, int],
    eye: tuple[int, int, int],
) -> Image.Image:
    """Stejný vzorec, jaký použije shader ve hře."""
    source = mask.load()
    out = Image.new("RGBA", mask.size)
    target = out.load()
    for y in range(mask.height):
        for x in range(mask.width):
            r, g, b, a = source[x, y]
            if a == 0:
                target[x, y] = (0, 0, 0, 0)
                continue
            light = SHADE[0] + (SHADE[1] - SHADE[0]) * r / 255.0
            glint = ACCENT_SHADE[0] + (ACCENT_SHADE[1] - ACCENT_SHADE[0]) * r / 255.0
            mix_g, mix_b = g / 255.0, b / 255.0
            rgb = []
            for channel in range(3):
                base = body[channel] * light
                skin = base + (accent[channel] * glint - base) * mix_g
                rgb.append(max(0, min(255, round(skin + (eye[channel] - skin) * mix_b))))
            target[x, y] = (rgb[0], rgb[1], rgb[2], a)
    return out


def glint_star(dx: float, dy: float) -> float:
    """Odlesk jako v crystal.gdshader: jádro a šest tenkých paprsků. dx, dy v px."""
    r2 = dx * dx + dy * dy
    core = math.exp(-r2 * 2.2)
    halo = math.exp(-r2 * 0.45) * 0.18
    rays = 0.0
    for ray in range(6):
        c, s = math.cos(ray * math.pi / 3), math.sin(ray * math.pi / 3)
        along = dx * c + dy * s
        across = abs(-dx * s + dy * c)
        arm = math.exp(-across * across * 5.5) * math.exp(-max(along, 0.0) * 0.55)
        edge = max(0.0, min(1.0, (along - 0.25) / 0.6))
        rays = max(rays, arm * edge * edge * (3.0 - 2.0 * edge))
    return core + halo + rays * 1.15


def sparkle(
    image: Image.Image,
    mask: Image.Image,
    glint: tuple[int, int, int],
    amount: float,
    clock: float,
) -> Image.Image:
    """Přičte odlesky k obarvené vrstvě v čase clock sekund. Semínka jsou vrcholy G v mask."""
    if amount <= 0.0:
        return image
    seeds = mask.getchannel("G").load()
    alpha = mask.getchannel("A").load()
    out = image.copy()
    pixels = out.load()
    width, height = mask.size
    reach = 6
    for y in range(height):
        for x in range(width):
            value = seeds[x, y]
            if value < 12 or alpha[x, y] < 128:
                continue
            around = [
                seeds[x + i, y + j]
                for j in (-1, 0, 1)
                for i in (-1, 0, 1)
                if 0 <= x + i < width and 0 <= y + j < height
            ]
            if value < max(around):
                continue
            wave = math.sin(clock * SPARKLE_SPEED + value / 255.0 * math.tau)
            flash = max(wave, 0.0) ** 14 * amount
            if flash < 0.02:
                continue
            for j in range(-reach, reach + 1):
                for i in range(-reach, reach + 1):
                    px, py = x + i, y + j
                    if not (0 <= px < width and 0 <= py < height) or alpha[px, py] == 0:
                        continue
                    light = flash * glint_star(i, j)
                    r, g, b, a = pixels[px, py]
                    pixels[px, py] = (
                        min(255, round(r + glint[0] * light)),
                        min(255, round(g + glint[1] * light)),
                        min(255, round(b + glint[2] * light)),
                        a,
                    )
    return out


def darken(mask: Image.Image) -> Image.Image:
    """Stínová vrstva tak, jak ji nakreslí hra: černá s krytím SHADOW_ALPHA."""
    image = Image.new("RGBA", mask.size, (0, 0, 0, 255))
    image.putalpha(mask.getchannel("A").point(lambda value: round(value * SHADOW_ALPHA)))
    return image


def preview_shadow(canvas: int, box: tuple[Point, Point] | None) -> Image.Image:
    if box is None:
        return blank(canvas)
    layer = Layer(canvas)
    x0, y0 = layer.px(box[0])
    x1, y1 = layer.px(box[1])
    big = Image.new("L", (canvas * SS, canvas * SS), 0)
    ImageDraw.Draw(big).ellipse((x0, y0, x1, y1), fill=60)
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 255))
    image.putalpha(big.resize((canvas, canvas), Image.Resampling.BOX))
    return image


def compose(
    sprites: dict[int, Image.Image],
    heights: dict[int, float],
    under: Image.Image,
    shift: Point = (0.0, 0.0),
) -> Image.Image:
    canvas = under.width
    image = blank(canvas)
    image.alpha_composite(under)
    for key in sorted(sprites):
        sprite = sprites[key]
        left = round((canvas - sprite.width) / 2 + shift[0] * heights[key])
        top = round((canvas - sprite.height) / 2 + shift[1] * heights[key])
        image.alpha_composite(sprite, (left, top))
    return image


def save_gif(frames: list[Image.Image], path: Path, scale: int, ms: int) -> None:
    rgb = []
    for frame in frames:
        grass = on_grass(frame)
        if scale != 1:
            grass = grass.resize((grass.width * scale, grass.height * scale), Image.Resampling.NEAREST)
        rgb.append(grass)
    path.parent.mkdir(parents=True, exist_ok=True)
    rgb[0].save(path, save_all=True, append_images=rgb[1:], duration=ms, loop=0, disposal=2)


def side_by_side(images: list[Image.Image]) -> Image.Image:
    strip = Image.new("RGBA", (sum(image.width for image in images), images[0].height), (0, 0, 0, 0))
    left = 0
    for image in images:
        strip.alpha_composite(image, (left, 0))
        left += image.width
    return strip


def materials_of(name: str) -> list[str]:
    """Materiály druhu a k nim preview_materials, od nejlevnějšího."""
    owned = [material for material, info in MATERIALS.items() if info.get("monster") == name]
    for material in MONSTERS[name].get("preview_materials", ()):
        if material not in owned:
            owned.append(material)
    return sorted(owned, key=lambda material: MATERIALS[material]["points"])


def palette(preset: dict, material: str) -> tuple[tuple[int, int, int], ...]:
    info = MATERIALS[material]
    return (
        parse_hex(info["color"]),
        parse_hex(info.get("monster_accent", info["glint"])),
        parse_hex(preset["eye"]),
    )


def check(name: str, preset: dict) -> None:
    if name not in RENDERERS:
        raise SystemExit(f"{name}: druh nemá kreslení")
    if not materials_of(name):
        raise SystemExit(f"{name}: žádný materiál v gen_crystal.MATERIALS nemá tuhle příšeru")


def check_materials() -> None:
    for material, info in MATERIALS.items():
        if info.get("monster") not in MONSTERS:
            raise SystemExit(f"{material}: neznámá příšera {info.get('monster')}")


def generate(name: str, preset: dict) -> dict:
    check(name, preset)
    render = RENDERERS[name]
    layers = preset["layers"]
    count = preset["frames"]
    stone = preset.get("info", {}).get("shader") == "stone"
    frames = {key: [] for key in layers}
    sparks = {key: [] for key in layers}
    for index in range(count):
        rendered = render(index / count)
        for key in layers:
            frames[key].append(pack(rendered[key], preset.get("zoom", 1.0)))
            if stone:
                sparks[key].append(pack_spark(rendered[key], frames[key][-1]))
    folder = OUT_DIR / name
    folder.mkdir(parents=True, exist_ok=True)
    entry = {}
    for key, info in layers.items():
        frames[key] = crop_square(frames[key])
        cell = frames[key][0].width
        pack_atlas(frames[key], COLUMNS).save(folder / info["file"])
        entry[str(key)] = {
            "height": info["height"],
            "file": f"{name}/{info['file']}",
            "cell": cell,
            "center": cell // 2,
        }
        if info.get("shadow"):
            entry[str(key)]["shadow"] = True
        if stone:
            sparks[key] = crop_square(sparks[key])
            spark_file = info["file"].replace(".png", "_spark.png")
            pack_atlas(sparks[key], COLUMNS).save(folder / spark_file)
            entry[str(key)]["sparkle_file"] = f"{name}/{spark_file}"
    write_previews(name, preset, frames, sparks)
    return {
        "cycle_meters": round(preset["cycle_meters"], 4),
        "frames": count,
        "atlas_columns": COLUMNS,
        "wander_meters": preset["wander_meters"],
        "chase_meters": preset["chase_meters"],
        "body_meters": preset["body_meters"],
        "height_meters": preset["height_meters"],
        "jump_meters": preset.get("jump_meters", 0.0),
        **preset.get("info", {}),
        "layers": entry,
        "colors": {"eye": preset["eye"]},
    }


def write_previews(
    name: str,
    preset: dict,
    frames: dict[int, list[Image.Image]],
    sparks: dict[int, list[Image.Image]] | None = None,
) -> None:
    layers = preset["layers"]
    heights = {key: info["height"] for key, info in layers.items()}
    materials = materials_of(name)
    count = preset["frames"]
    # Přehledy ukazují stejné fáze cyklu bez ohledu na počet snímků.
    step = max(1, count // SHEET_FRAMES)
    # Plátno pojme i vrstvu posunutou „u kraje“.
    drift = math.ceil(max(abs(EDGE[0]), abs(EDGE[1])) * max(heights.values()))
    size = max(preset["canvas"], max(frames[key][0].width for key in frames) + 2 * drift + 4)
    box = preset["preview_shadow"]
    zoom = preset.get("zoom", 1.0)
    if box is not None:
        box = tuple((x * zoom, y * zoom) for x, y in box)
    under = preview_shadow(size + size % 2, box)

    stone = preset.get("info", {}).get("shader") == "stone"

    def tint(key: int, mask: Image.Image, colors: tuple[tuple[int, int, int], ...]) -> Image.Image:
        if layers[key].get("shadow"):
            return darken(mask)
        return colorize(mask, *colors)

    def walk(material: str, shift: Point = (0.0, 0.0)) -> list[Image.Image]:
        colors = palette(preset, material)
        return [
            compose({key: tint(key, frames[key][index], colors) for key in frames}, heights, under, shift)
            for index in range(count)
        ]

    def twinkle(material: str) -> list[Image.Image]:
        """SPARKLE_CYCLES cyklů chůze s blikáním odlesků, jak ho kreslí monster_stone_layer."""
        colors = palette(preset, material)
        info = MATERIALS[material]
        glint, amount = parse_hex(info["glint"]), float(info["sparkle"])
        total = count * SPARKLE_CYCLES
        out = []
        for index in range(total):
            clock = index / total * SPARKLE_PERIOD
            sprites = {
                key: sparkle(tint(key, frames[key][index % count], colors), sparks[key][index % count], glint, amount, clock)
                for key in frames
            }
            out.append(compose(sprites, heights, under))
        return out

    walks = {material: crop_square(walk(material)) for material in materials}
    first = walks[materials[0]]
    scale = math.ceil(300 / first[0].width)
    small = max(1, scale - 1)
    # GIF ukládá délku snímku v setinách sekundy.
    ms = 10 * max(2, round(preset.get("preview_cycle_ms", PREVIEW_CYCLE_MS) / count / 10))
    save_gif(first, PREVIEW / f"{name}.gif", scale, ms)
    shown = range(0, count, step)
    contact_sheet(
        [first[index] for index in shown],
        [f"snímek {index}" for index in shown],
        PREVIEW / f"{name}_chuz.png",
        small,
    )
    if any(info.get("shadow") for info in layers.values()):
        save_gif(crop_square(walk(materials[0], EDGE)), PREVIEW / f"{name}_u_kraje.gif", scale, ms)

    colors = palette(preset, materials[0])
    sprites = {key: tint(key, frames[key][step], colors) for key in frames}
    panels = [compose({key: sprites[key]}, heights, under) for key in sorted(sprites)]
    panels += [compose(sprites, heights, under), compose(sprites, heights, under, EDGE)]
    labels = [
        f"{'stín' if layers[key].get('shadow') else f'vrstva {key}'} · {heights[key]:g} m" for key in sorted(sprites)
    ] + ["spolu", "u kraje"]
    contact_sheet(crop_square(panels), labels, PREVIEW / f"{name}_vrstvy.png", scale)

    contact_sheet(
        [walks[material][step] for material in materials],
        materials,
        PREVIEW / f"{name}_materialy.png",
        scale,
    )
    strips = [side_by_side([walks[material][index] for material in materials]) for index in range(count)]
    save_gif(strips, PREVIEW / f"{name}_materialy.gif", small, ms)
    if stone:
        shining = {material: crop_square(twinkle(material)) for material in materials}
        strips = [side_by_side([shining[material][index] for material in materials]) for index in range(count * SPARKLE_CYCLES)]
        save_gif(strips, PREVIEW / f"{name}_trpyt.gif", small, ms)


def write_info(species: dict) -> Path:
    """Doplní vygenerované druhy ke druhům, které už v katalogu jsou."""
    known = {}
    if INFO_PATH.exists():
        known = json.loads(INFO_PATH.read_text(encoding="utf-8")).get("species", {})
    known.update(species)
    catalog = {
        "px_per_meter": PX_PER_METER,
        "facing": "N",
        "filter": "linear",
        "channels": ["shade", "accent", "eye"],
        "shade": list(SHADE),
        "accent_shade": list(ACCENT_SHADE),
        "shadow_alpha": SHADOW_ALPHA,
        "species": {name: known[name] for name in MONSTERS if name in known},
    }
    INFO_PATH.parent.mkdir(parents=True, exist_ok=True)
    INFO_PATH.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return INFO_PATH


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--name", choices=sorted(MONSTERS), help="jen jeden druh")
    args = parser.parse_args()
    check_materials()
    names = [args.name] if args.name else list(MONSTERS)
    species = {}
    for name in names:
        species[name] = generate(name, MONSTERS[name])
        cells = "–".join(str(layer["cell"]) for layer in species[name]["layers"].values())
        print(f"{name}: buňky {cells}, cyklus {species[name]['cycle_meters']} m")
        print(PREVIEW / f"{name}.gif")
    print(write_info(species))


if __name__ == "__main__":
    main()
