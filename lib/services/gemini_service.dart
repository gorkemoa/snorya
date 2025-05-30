import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../utils/constants.dart';
import '../models/game.dart';

class GeminiService {
  final GenerativeModel _model;

  GeminiService() : _model = GenerativeModel(
    model: 'gemini-2.0-flash',
    apiKey: AppConstants.geminiApiKey,
  );

  /// Wikipedia makale içeriğinden özet oluşturur
  Future<String> generateSummary(String articleContent) async {
    try {
      // Çok uzun bir içerikse kısalt
      final String trimmedContent = articleContent.length > 10000 
          ? articleContent.substring(0, 10000) 
          : articleContent;
      
      // Gemini prompt'unu oluştur
      final prompt = '${AppConstants.geminiPrompt}\n\n$trimmedContent';
      
      // Özet talep et
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      
      // Yanıtı kontrol et
      if (response.text != null && response.text!.isNotEmpty) {
        return response.text!;
      } else {
        return AppConstants.fallbackSummary;
      }
    } catch (e) {
      return AppConstants.fallbackSummary;
    }
  }
  
  /// Oyun önerisi oluşturur
  /// [query] Kullanıcının girdisi (GTA tarzı oyun, RPG oyunu vs.)
  Future<List<Game>> generateGameRecommendation(String query) async {
    try {
      final prompt = '''Kullanıcının isteğine göre bir oyun önerisi sun. 
Yanıtını SADECE aşağıdaki JSON formatında ver, hiçbir açıklama veya ek metin ekleme:

{
  "title": "Oyunun tam adı",
  "genre": "Ana tür/kategori",
  "platform": "Oyunun oynandığı platformlar (PC, PlayStation, Xbox, vb.)",
  "summary": "Oyunun 2-3 cümlede Türkçe özeti",
  "content": "Oyunun 10-15 cümlede Türkçe olarak detaylı açıklaması, öne çıkan özellikleri, oynanış özellikleri",
  "searchTitle": "Wikipedia'da arama yapılacak başlık"
}

Kullanıcı isteği: $query''';
      
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      
      if (response.text != null && response.text!.isNotEmpty) {
        try {
          // Cevaptaki JSON formatını çıkar
          String jsonText = response.text!;
          
          // Debug: Yanıtı kontrol et
          print("API yanıtı: ${jsonText}");
          
          // Cevap içerisinde JSON olarak formatlı metni ayıkla
          // Farklı olası formatları ele al
          if (jsonText.contains("{") && jsonText.contains("}")) {
            int startIndex = jsonText.indexOf('{');
            int endIndex = jsonText.lastIndexOf('}') + 1;
            
            if (startIndex >= 0 && endIndex > startIndex) {
              jsonText = jsonText.substring(startIndex, endIndex);
            }
          }
          
          jsonText = jsonText.replaceAll("```json", "").replaceAll("```", "").trim();
          
          // String'i Map'e dönüştür
          final Map<String, dynamic> gameData = Map<String, dynamic>.from(
            jsonDecode(jsonText)
          );
          
          // Gerekli alanların varlığını kontrol et ve varsayılan değerler kullan
          final title = gameData['title'] ?? 'Oyun Önerisi';
          final genre = gameData['genre'] ?? 'Genel';
          final platform = gameData['platform'] ?? '';
          final summary = gameData['summary'] ?? 'Bilgi bulunamadı.';
          final content = gameData['content'] ?? 'Detaylı içerik bulunamadı.';
          final searchTitle = gameData['searchTitle'] ?? title;
          
          // Game modeli oluştur - görsel Wikipedia'dan ayrıca alınacak
          return [
            Game(
              title: title,
              genre: genre,
              platform: platform,
              summary: summary,
              content: content,
              imageUrl: '', // Görsel sonradan Wikipedia servisi ile doldurulacak
              metadata: {
                'searchTitle': searchTitle,
                'originalQuery': query,
              },
            )
          ];
        } catch (e) {
          print("JSON ayrıştırma hatası: $e");
          print("Hatalı yanıt: ${response.text}");
          
          // JSON parse hatası durumunda alternatif ayrıştırma deneyelim
          try {
            // Metin içinden bilgileri manuel olarak çıkaralım
            String text = response.text ?? '';
            
            // Başlık, tür ve platform bilgilerini bulmaya çalış
            String title = _extractField(text, 'title', 'Oyun Önerisi');
            String genre = _extractField(text, 'genre', 'Genel');
            String platform = _extractField(text, 'platform', '');
            String summary = _extractField(text, 'summary', 'Önerinin özet bilgisi alınamadı.');
            String content = _extractField(text, 'content', 'Detaylı içerik alınamadı.');
            String searchTitle = _extractField(text, 'searchTitle', title);
            
            // En azından başlık ve özet bulunabildi mi kontrol et
            if (title != 'Oyun Önerisi' || summary != 'Önerinin özet bilgisi alınamadı.') {
              return [
                Game(
                  title: title,
                  genre: genre,
                  platform: platform,
                  summary: summary,
                  content: content,
                  imageUrl: '',
                  metadata: {
                    'searchTitle': searchTitle,
                    'originalQuery': query,
                    'parseMethod': 'Manuel ayrıştırma',
                  },
                )
              ];
            }
            
            // Manuel ayrıştırma da olmadıysa
            return [
              Game(
                title: 'Format Hatası',
                genre: 'Bilinmiyor',
                summary: 'Önerilen oyun bilgileri işlenirken hata oluştu.',
                content: 'Önerilen oyun bilgileri işlenirken bir hata oluştu. API yanıtı: ' + 
                        ((response.text?.length ?? 0) > 100 
                          ? response.text!.substring(0, 100) + '...' 
                          : (response.text ?? 'Boş yanıt')),
                imageUrl: '',
              )
            ];
          } catch (manualExtractError) {
            print("Manuel ayrıştırma da başarısız: $manualExtractError");
            return [
              Game(
                title: 'Format Hatası',
                genre: 'Bilinmiyor',
                summary: 'Önerilen oyun bilgileri işlenirken hata oluştu.',
                content: 'Önerilen oyun bilgileri işlenirken bir hata oluştu. Lütfen tekrar deneyin.',
                imageUrl: '',
              )
            ];
          }
        }
      } else {
        return [
          Game(
            title: 'Öneri Bulunamadı',
            genre: 'Bilinmiyor',
            summary: 'Aradığınız kriterlere uygun oyun önerisi bulunamadı.',
            content: 'Aradığınız kriterlere uygun oyun önerisi bulunamadı. Lütfen farklı arama kriterleri ile tekrar deneyin.',
            imageUrl: '',
          )
        ];
      }
    } catch (e) {
      print("Oyun önerisi alma hatası: $e");
      return [
        Game(
          title: 'Hata Oluştu',
          genre: 'Bilinmiyor',
          summary: 'Oyun önerisi alınırken bir hata oluştu.',
          content: 'Yapay zeka servisinden oyun önerisi alınırken bir hata oluştu. Lütfen tekrar deneyin. Hata: ' + e.toString(),
          imageUrl: '',
        )
      ];
    }
  }

  /// Metin içinden belirli bir alanı çıkarmaya çalışır
  String _extractField(String text, String fieldName, String defaultValue) {
    // "title": "Oyun adı" veya "title" : "Oyun adı" gibi kalıpları ara
    final RegExp regExp = RegExp(
      '["\']*$fieldName["\']*\\s*[:=]\\s*["\'](.*?)["\']',
      caseSensitive: false
    );
    
    final match = regExp.firstMatch(text);
    if (match != null && match.groupCount >= 1) {
      return match.group(1) ?? defaultValue;
    }
    
    // Alan adını bulup ondan sonraki metni almayı dene
    final int fieldIndex = text.toLowerCase().indexOf(fieldName.toLowerCase());
    if (fieldIndex != -1) {
      final int colonIndex = text.indexOf(':', fieldIndex);
      if (colonIndex != -1) {
        final int valueStart = colonIndex + 1;
        int valueEnd = text.indexOf('\n', valueStart);
        if (valueEnd == -1) {
          valueEnd = text.indexOf(',', valueStart);
        }
        if (valueEnd == -1) {
          valueEnd = text.length;
        }
        
        if (valueEnd > valueStart) {
          final String value = text.substring(valueStart, valueEnd).trim();
          // Tırnak işaretlerini kaldır
          return value.replaceAll('"', '').replaceAll("'", '').trim();
        }
      }
    }
    
    return defaultValue;
  }

  /// Belirli bir oyun için gerçek puanları ve değerlendirmeleri getir
  Future<Map<String, dynamic>> fetchGameReviewsAndRatings(String gameTitle) async {
    try {
      final prompt = '''Lütfen "${gameTitle}" oyunu için GERÇEKLİĞİ doğrulanabilir, GERÇEK puanları ve yorumlarını aşağıdaki sıkı JSON formatında ver:
      {
        "ratings": {
          "metacritic": {
            "score": [0-100 arası sayı veya null (bilinmiyorsa)],
            "count": [kaç değerlendirme olduğu, bilinmiyorsa null],
            "url": "metacritic sayfasının tam URL'i"
          },
          "ign": {
            "score": [0-10 arası sayı veya null],
            "reviewer": "Eleştirmenin adı (bilinmiyorsa boş)",
            "summary": "Kısa özet (varsa, yoksa boş)"
          },
          "steam": {
            "positive_percent": [pozitif yorumların yüzdesi veya null],
            "review_count": [toplam değerlendirme sayısı veya null],
            "summary": "Kullanıcı değerlendirme özeti (Çok Olumlu, Olumlu, Karma, vb.)"
          }
        },
        "reviews": [
          {
            "source": "Kaynak site/dergi ismi",
            "author": "Eleştirmenin adı",
            "score": "Puan (10 üzerinden 8 gibi)",
            "comment": "Eleştirmenin yaptığı kısa yorum veya değerlendirme (1-2 cümle)",
            "date": "Değerlendirme tarihi (biliniyorsa)"
          }
        ],
        "data_availability": "tam" | "kısmi" | "bulunamadı"
      }
      
      ÖNEMLİ:
      - SADECE GERÇEK ve DOĞRULANMIŞ veriler kullan. Yanlış bilgi vermektense "null" veya boş değerler tercih edilmelidir.
      - Eğer oyun hakkında yeterli değerlendirme veya puan verisi bulamıyorsan data_availability alanını "bulunamadı" olarak ayarla.
      - Değerlendirmeler ve puanlar TÜRKÇE olmalıdır.
      - Steam'de oyun yoksa Steam alanını boş bırak.
      - Değerlendirmeler bölümünde en az 2, en fazla 5 farklı ve GERÇEK yorum ekle.
      - Herhangi bir açıklama veya ek metin ekleme, SADECE JSON döndür.''';
      
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      
      if (response.text != null && response.text!.isNotEmpty) {
        try {
          // JSON formatına çevirme
          String jsonText = response.text!;
          
          // Debug: Yanıtı kontrol et
          print("API yanıtı (puanlar ve yorumlar): ${jsonText}");
          
          // JSON'ı ayıkla
          if (jsonText.contains("{") && jsonText.contains("}")) {
            int startIndex = jsonText.indexOf('{');
            int endIndex = jsonText.lastIndexOf('}') + 1;
            
            if (startIndex >= 0 && endIndex > startIndex) {
              jsonText = jsonText.substring(startIndex, endIndex);
            }
          }
          
          jsonText = jsonText.replaceAll("```json", "").replaceAll("```", "").trim();
          
          // JSON'ı parse et
          final Map<String, dynamic> reviewData = Map<String, dynamic>.from(
            jsonDecode(jsonText)
          );
          
          // 'reviews' alanını doğru formata dönüştür
          if (reviewData.containsKey('reviews') && reviewData['reviews'] is List) {
            List<dynamic> reviewsList = reviewData['reviews'] as List<dynamic>;
            reviewData['reviews'] = reviewsList
                .map((item) => item is Map 
                    ? Map<String, dynamic>.from(item) 
                    : <String, dynamic>{})
                .toList();
          }
          
          return reviewData;
        } catch (e) {
          print("JSON ayrıştırma hatası (değerlendirmeler): $e");
          // Hata durumunda boş veri döndür
          return {
            "ratings": {},
            "reviews": [],
            "data_availability": "bulunamadı",
            "error": "Veri formatı hatası: $e"
          };
        }
      } else {
        return {
          "ratings": {},
          "reviews": [],
          "data_availability": "bulunamadı",
          "error": "Yanıt alınamadı"
        };
      }
    } catch (e) {
      print("Oyun değerlendirmeleri getirme hatası: $e");
      return {
        "ratings": {},
        "reviews": [],
        "data_availability": "bulunamadı",
        "error": "Hata: $e"
      };
    }
  }

  /// Genel içerik üretme metodu
  Future<String> generateContent(String prompt) async {
    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      
      if (response.text != null && response.text!.isNotEmpty) {
        return response.text!;
      } else {
        return '';
      }
    } catch (e) {
      print('Gemini içerik üretme hatası: $e');
      return '';
    }
  }
} 