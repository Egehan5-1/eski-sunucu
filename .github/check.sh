#!/bin/bash
# PR kontrolü. pull_request_target ile main'deki bu betik çalışır; PR'ın kodu
# ASLA checkout edilmez, çalıştırılmaz. Değişen dosya GitHub API'sinden veri
# olarak okunur. Sır (bayrak HMAC anahtarı) yalnız burada, Actions secret'ında.
#
# İki parça: dogrula() saf doğrulama (yerelde test edilebilir), main() gh ile
# girdileri toplar ve dogrula()'yı çağırır.
set -uo pipefail

# Türkçe, somut hata mesajı biriktir; sonda PR'a yorum olarak yazılır.
HATA=""
hata() { HATA="${HATA}- $1"$'\n'; }

# dogrula <author> <title> <secret> <tek_dosya_yolu> <json_icerik_dosyasi>
# Dönüş: 0 geçti, 1 kaldı. Mesajlar $HATA'da.
dogrula() {
    local author="$1" title="$2" secret="$3" yol="$4" icerik_dosya="$5"
    HATA=""

    # 1) Dosya yolu tam admins/<author>.json olmalı.
    if [ "$yol" != "admins/${author}.json" ]; then
        hata "Dosyanın adı admins/${author}.json olmalı; gelen: ${yol}. Betiğin verdiği bağlantıyı kullan."
    fi

    # 2) Geçerli JSON mu?
    if ! jq empty "$icerik_dosya" 2>/dev/null; then
        hata "Dosya geçerli bir JSON değil. Süslü parantezleri ve tırnakları kontrol et."
        printf '%s' "$HATA"; return 1   # JSON bozuksa alan kontrolleri anlamsız
    fi

    # 3) github alanı PR sahibiyle aynı mı?
    local g; g="$(jq -r '.github // empty' "$icerik_dosya")"
    if [ "$g" != "$author" ]; then
        hata "JSON'daki github alanı (${g:-boş}) seninle (${author}) aynı değil."
    fi

    # 4) hardest_part boş değil ve BURAYI DOLDUR değil.
    local z; z="$(jq -r '.hardest_part // empty' "$icerik_dosya")"
    if [ -z "$z" ] || [ "$z" = "BURAYI DOLDUR" ]; then
        hata "hardest_part boş. become-admin betiğini çalıştırırken o soruyu doldur."
    fi

    # 5) Bayrak, sırla yeniden hesaplanan değere eşit mi?
    local b beklenen ham
    b="$(jq -r '.flag // empty' "$icerik_dosya")"
    ham="$(printf '%s' "$author" | openssl dgst -sha256 -hmac "$secret" -hex 2>/dev/null | awk '{print $NF}')"
    beklenen="GDG{${ham:0:32}}"
    if [ "$b" != "$beklenen" ]; then
        hata "Bayrak doğru değil. ./gate sana senin kullanıcı adına özel bir bayrak vermişti; onu yapıştır."
    fi

    # 6) PR başlığı doğru biçimde mi? (squash birleşmede başlık commit olur)
    if ! printf '%s' "$title" | grep -Eq '^feat\(admins\): '; then
        hata "PR başlığı 'feat(admins): ' ile başlamalı. Örnek: feat(admins): add ${author}"
    fi

    if [ -n "$HATA" ]; then printf '%s' "$HATA"; return 1; fi
    return 0
}

main() {
    local repo="${GITHUB_REPOSITORY:?}" pr="${PR_NUMARA:?}" author="${PR_SAHIBI:?}"
    local title="${PR_BASLIK:?}" secret="${BAYRAK_SIRRI:?}" sha="${PR_HEAD_SHA:?}"

    # TOCTOU koruması: her şey SABİT head SHA'ya göre doğrulanır; iş akışının
    # merge adımı da --match-head-commit ile aynı SHA'yı ister. Böylece
    # doğrulama ile birleşme arasında PR'a yeni commit atılırsa merge iptal
    # olur; doğruladığımız tam olarak birleşen şeydir.
    local base; base="$(gh api "repos/${repo}" --jq '.default_branch')"

    # Değişen dosyaları SABİT SHA'ya göre al (compare API), durumlarıyla.
    local files_json; files_json="$(gh api "repos/${repo}/compare/${base}...${sha}" \
        --jq '[.files[] | {filename, status, previous_filename}]')"
    local adet; adet="$(printf '%s' "$files_json" | jq 'length')"
    if [ "$adet" -ne 1 ]; then
        hata "PR yalnız tek bir dosya değiştirmeli (senin admins dosyan). Gelen $adet dosya."
        printf '%s' "$HATA"; return 1
    fi
    local yol durum onceki
    yol="$(printf '%s' "$files_json" | jq -r '.[0].filename')"
    durum="$(printf '%s' "$files_json" | jq -r '.[0].status')"
    onceki="$(printf '%s' "$files_json" | jq -r '.[0].previous_filename // ""')"
    # Yeniden adlandırma reddedilir: başkasının dosyasını taşıyıp silebilir.
    if [ -n "$onceki" ]; then
        hata "Bir dosyayı yeniden adlandırma; yalnız kendi admins/<kullanici>.json dosyanı ekle."
        printf '%s' "$HATA"; return 1
    fi
    # Yalnız ekleme ya da kendi dosyanı güncelleme; silme/kopyalama değil.
    case "$durum" in
        added|modified) ;;
        *) hata "Dosya durumu '$durum' kabul edilmiyor; yalnız kendi dosyanı ekle."
           printf '%s' "$HATA"; return 1 ;;
    esac

    # Dosya içeriğini SABİT SHA'dan veri olarak çek (checkout yok, head oynasa
    # bile bu SHA sabit).
    local tmp; tmp="$(mktemp)"
    gh api "repos/${repo}/contents/${yol}?ref=${sha}" --jq '.content' 2>/dev/null | base64 -d > "$tmp"

    if dogrula "$author" "$title" "$secret" "$yol" "$tmp"; then
        echo "kullanici=${author}" >> "${GITHUB_OUTPUT:-/dev/stdout}"
        return 0
    fi
    return 1
}

# Doğrudan çalıştırılırsa main; source edilirse yalnız fonksiyonlar gelir.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main
fi
