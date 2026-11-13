# eski.ikcu.dev yoneticiler listesi

Bu, eski sunucunun yoneticiler listesidir. Listeye girmek icin sunucuya kendin
ulasip, orada birakilan `become-admin` betiginin verdigi baglantiyi kullan.

- Her yonetici `admins/<github-kullanici-adin>.json` dosyasini ekler.
- Dosyayi elle kurma; betigin verdigi hazir baglantiyi ac, geleni gonder.
- Acilan PR otomatik kontrolden gecer; yesil olursa listeye eklenirsin,
  kirmizi olursa bot neyin eksik oldugunu Turkce yazar.

Dosya bicimi:

```json
{
  "github": "kullanici-adin",
  "flag": "GDG{...}",
  "hardest_part": "..."
}
```

Takilirsan yardim kanalina yaz.
