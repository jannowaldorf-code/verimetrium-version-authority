# GVA-K03 — püsiv privaatne VERIMETRIUM ZIP-väljastus

**Roll:** privaatse GitHub Releases'i transpordi ja SHA-256 kaudu kontrollitava Windowsi D:\DADA arhiivi haldamine. Ei väljasta globaalseid versiooninumbreid, ei muuda `gva/registry.json` ega lükka ühtegi uuringu ZIP-i avalikku hoidlas.

## Esimene käivitamine (Windows PowerShell)

1. Paigalda ametlik GitHub CLI `gh` aadressilt https://cli.github.com/, kui puudub.
2. Autendi lokaalselt: `gh auth login -h github.com -p https -w` (ära saada paroole või tokeneid vestlusesse).
3. `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\GVA_K03_RELEASE_DELIVERY.ps1 -Action SelfTest`
4. `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\GVA_K03_RELEASE_DELIVERY.ps1 -Action Setup`
5. Veendu, et GitHubi hoidla `jannowaldorf-code/verimetrium-deliveries` on **PRIVATE** ja `Settings > Releases > Enable release immutability` on sisse lülitatud. `Setup` proovib seda API kaudu ise sisse lülitada ja kontrollib tulemust; kui kontol puudub admin õigus, peab kasutaja selle seadistuse GitHubi UI-st käsitsi lubama. Avalikus `verimetrium-version-authority` hoidlas on lubatud üksnes avalik metadata.

## Esimene W04.3.8.15.4 üleslaadimine

Kui W04 täielik 119,35 MB ZIP on Windowsis saadaval (nt `D:\DADA\...`), käivita:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\GVA_K03_RELEASE_DELIVERY.ps1 -Action Publish -Channel PROOF -WorkId W0438154 -AssetPath 'D:\DADA\VERIMETRIUM_W04_3_8_15_4_GL_RIGHTS_POLICY_DECISION_MATHEMATICAL_TRUTH_SEPARATION_COMPLETE.zip'
```

Skript teeb olemasoleva hoidla privaatsuskontrolli, SHA256 arvutuse, tagi, privaatse `PROOF` pre-release'i koos `GVA_K03_DELIVERY_MANIFEST.json`-ga ning laadib ZIP-i GitHubist **tagasi** sõltumatu kontrollsummatesti jaoks. Ta ei asenda ega kustuta olemasolevat Release'i. Uurimisandmeid ei muudeta.

## Uuesti allalaadimine

Tag on kujul `proof-w0438154-<SHA256 esimesed 16 märki>`. W04.3.8.15.4 korral:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\GVA_K03_RELEASE_DELIVERY.ps1 -Action Fetch -Tag proof-w0438154-1f3371d2e7bb5df9
```

Andmed salvestatakse kontrollitult `D:\DADA\VERIMETRIUM_RELEASES\<tag>\verified\`.

## Ametliku GVA väljalaske kaitse

`-Channel OFFICIAL` nõuab olemasolevat `Vxxxx.xx` kirjet **avalikus kaitstud registris** ning täpselt sama `work` ja `source_set_sha256` väärtust. GVA-K03 ei väljasta uut numbrit; ükski `REL` ei teki iseseisvalt. Avalik register `gva/registry.json` on muutumatu.

## Piirid ja tõendamine

- GitHub CLI algne autentimine, privaatse hoidla loomine ning 119 MB ZIP-i üles- ja tagasilaadimine tuleb Windowsis esimest korda päriselt käivitada. Kuni seda pole tehtud, on **GitHubi väljalaskekanal PENDING**, mitte PASS.
- Käesolevast ChatGPT keskkonnast ei saa suurte failide otseüleslaadimist teha. Esimene ZIP tuleb saada Windowsisse ühe korra (nt varem talletatud osadest). Edaspidi on privaatne GitHub Releases peamine kanal.
- Kasutaja olemasolev GitHub self-hosted runner on seotud muu töövooga; uus privaatne hoidla ei saa runner'i õigusi automaatselt. See skript töötab otse Windowsis ega nõua runner'i ümbersidumist.
- Sama `proof` tagi korral teise SHA-256-ga faili ei avaldata; uus erinev fail saab uue tõendus-tagi.
- GitHub Release ei ole iseenesest maakleri täitmistõend ega digitaalallkiri; manifesti sha kontrollib edastatud baitide identsust.

GitHubi algseadistus on failisuurete ja avaldamisvolituste mõttes autentimisest sõltuv: kuni kasutaja pole Windowsis `Setup` ja esimest `Publish` käivitanud, ei ole kanali tegelik avaldamine kinnitatud.
