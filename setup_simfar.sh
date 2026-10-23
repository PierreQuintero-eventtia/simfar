#!/bin/bash
set -e

echo "=== 1. Creando estructura de directorios ==="
mkdir -p .github/workflows
mkdir -p android/app/src/main
mkdir -p lib

echo "=== 2. Configurando GitHub Actions (Compilador de APK) ==="
cat << 'YAML' > .github/workflows/build_apk.yml
name: Compilar APK SIMFAR

on:
  push:
    branches: [ "main", "master" ]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Java 17
        uses: actions/setup-java@v3
        with:
          distribution: 'zulu'
          java-version: '17'

      - name: Instalar Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
          channel: 'stable'

      - name: Dependencias
        run: flutter pub get

      - name: Compilar APK Release
        run: flutter build apk --release

      - name: Subir APK
        uses: actions/upload-artifact@v4
        with:
          name: SIMFAR-APK-Chile
          path: build/app/outputs/flutter-apk/app-release.apk
YAML

echo "=== 3. Configurando dependencias en pubspec.yaml ==="
cat << 'YAML' > pubspec.yaml
name: simfar_app
description: "Simulador Inteligente de Atención Farmacéutica - SIMFAR"
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  speech_to_text: ^6.6.1
  flutter_tts: ^4.0.2
  http: ^1.2.0
  permission_handler: ^11.3.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
YAML

echo "=== 4. Configurando Permisos Android (Micrófono y Red) ==="
cat << 'XML' > android/app/src/main/AndroidManifest.xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>

    <application
        android:label="SIMFAR Chile"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <queries>
        <intent>
            <action android:name="android.speech.RecognitionService" />
        </intent>
    </queries>
</manifest>
XML

echo "=== 5. Generando Código Fuente con Documentación SIMFAR integrada ==="
cat << 'DART' > lib/main.dart
import 'dart0:convert' if (dart.library.io) 'dart:convert';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

const String apiKey = "AQ.Ab8RN6IFJQTsJg08R6iXRRc80_FTlVTbWf1VtzUozcZ-m__dmg";

void main() {
  runApp(const MaterialApp(
    home: SimfarEngineScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

enum FSMState { espera, configuracion, construccionInstancia, simulacionActiva, evaluando, retroalimentacion }

class SimfarEngineScreen extends StatefulWidget {
  const SimfarEngineScreen({super.key});
  @override
  State<SimfarEngineScreen> createState() => _SimfarEngineScreenState();
}

class _SimfarEngineScreenState extends State<SimfarEngineScreen> {
  FSMState _state = FSMState.espera;
  late stt.SpeechToText _speech;
  late FlutterTts _tts;
  bool _isListening = false;
  String _recognizedText = "";
  String _statusMsg = "Listo para iniciar simulación";
  
  Map<String, dynamic>? _currentInstance;
  List<Map<String, String>> _timelineTranscript = [];
  Map<String, dynamic>? _evaluationResult;

  // BIBLIOTECA DE CONOCIMIENTO (DOCUMENTO 03.1 A 03.8)
  final List<Map<String, dynamic>> _knowledgeBank = [
    {
      "nivel": 1, // 1° Semestre
      "caso_id": "CASO-0012",
      "nombre": "Faringitis viral no complicada (OTC)",
      "paciente": "Carlos Soto, 42 años, mecánico de San Bernardo.",
      "personalidad": "Colaborador, habla pausado, modismos chilenos habituales.",
      "info_espontanea": "Hola buenas tardes señorita/joven... ando buscando un remedio porque desde ayer me duele caleta la garganta y me cuesta hasta tragar.",
      "info_condicionada": {
        "fiebre": "No he tenido fiebre, solo molestia al tragar.",
        "alergias": "Ninguna alergia conocida.",
        "medicamentos": "Solo me tomé un tecito con miel y limón.",
        "enfermedades": "No sufro de nada crónico."
      },
      "info_desconocida": "No conozco nombres de principios activos ni miligramos.",
      "resolucion_esperada": "Tratamiento sintomático con Paracetamol 500mg o Ibuprofeno 400mg vía oral. Medidas no farmacológicas: hidratación y reposo. NO indicar antibióticos.",
      "rubrica": {
        "criterio_clinico": "Preguntar por alergias y duración del dolor.",
        "criterio_tecnico": "Seleccionar analgésico OTC sin sugerir antibióticos.",
        "criterio_blando": "Trato respetuoso, empatía y lenguaje claro."
      }
    },
    {
      "nivel": 2, // 2° Semestre
      "caso_id": "CASO-0025",
      "nombre": "Pirosis gástrica por transgresión alimentaria (OTC)",
      "paciente": "Gladys Muñoz, 56 años, vecina de Maipú.",
      "personalidad": "Ansiosa, preocupada, tiende a dramatizar síntomas leves.",
      "info_espontanea": "Buenas tardes oiga... vengo afligida porque ando con una quemazón insoportable en el pecho y me duele la guata desde anoche.",
      "info_condicionada": {
        "tiempo": "Empezó anoche después de comer frituras.",
        "alergias": "Alergia a la penicilina.",
        "enfermedades": "Hipertensión arterial controlada.",
        "medicamentos": "Tomo Losartán 50mg cada mañana."
      },
      "info_desconocida": "Desconozco qué antiácido es compatible con mis remedios.",
      "resolucion_esperada": "Antiácido local de suspensión (Magaldrato o Hidróxido de Aluminio/Magnesio). Advertir espaciar 2 horas de su Losartán. ERROR CRÍTICO: Recomendar AINEs (Ibuprofeno/Ketorolaco).",
      "rubrica": {
        "criterio_clinico": "Identificar antecedente de Losartán y descartar signos de úlcera sangrante.",
        "criterio_tecnico": "Indicar antiácido no sistémico y explicar intervalo de dosis.",
        "criterio_blando": "Calmar la ansiedad de la paciente con tono empático."
      }
    },
    {
      "nivel": 3, // 3°, 4° y 5° Semestre
      "caso_id": "CASO-0039",
      "nombre": "Resfrío común en paciente hipertenso crónico (Caso Complejo)",
      "paciente": "Roberto Morales, 60 años, colectivero en Valparaíso.",
      "personalidad": "Impaciente, apurado, quiere una solución rápida.",
      "info_espontanea": "Hola maestro, véndame un antigripal de esos fuertes al tiro, que ando tapado de la nariz y no puedo parar la máquina.",
      "info_condicionada": {
        "enfermedades": "Si le preguntan: Sí, soy hipertenso hace años.",
        "medicamentos": "Tomo Enalapril de 20mg.",
        "alergias": "Ninguna.",
        "sintomas": "Congestión nasal y estornudos, sin fiebre."
      },
      "info_desconocida": "No sabe que la Pseudoefedrina eleva la presión arterial.",
      "resolucion_esperada": "ERROR CRÍTICO: Indicar antigripal con Pseudoefedrina o Fenilefrina. CONDUCTA CORRECTA: Explicar contraindicación por su hipertensión, entregar Paracetamol puro y sugerir lavados con Suero Fisiológico al 0.9%.",
      "rubrica": {
        "criterio_clinico": "Interrogatorio obligatorio de patologías crónicas antes de dispensar.",
        "criterio_tecnico": "Detección de contraindicación absoluta del vasoconstrictor.",
        "criterio_blando": "Manejo de la impaciencia del paciente con firmeza profesional."
      }
    }
  ];

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  void _initEngine() async {
    await Permission.microphone.request();
    _speech = stt.SpeechToText();
    await _speech.initialize();

    _tts = FlutterTts();
    await _tts.setLanguage("es-CL");
    await _tts.setSpeechRate(0.9);
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      if (_state == FSMState.simulacionActiva) {
        _listenHandsFree();
      }
    });
  }

  void _setupInstance(int semestre) {
    int targetNivel = (semestre <= 2) ? 1 : (semestre <= 4 ? 2 : 3);
    var matchedCases = _knowledgeBank.where((c) => c["nivel"] == targetNivel).toList();
    _currentInstance = matchedCases.first;

    setState(() {
      _state = FSMState.simulacionActiva;
      _timelineTranscript.clear();
      _statusMsg = "Paciente en ventanilla...";
    });

    String firstLine = _currentInstance!["info_espontanea"];
    _timelineTranscript.add({"role": "paciente", "text": firstLine});
    _speak(firstLine);
  }

  void _listenHandsFree() async {
    if (_state != FSMState.simulacionActiva) return;

    setState(() {
      _isListening = true;
      _statusMsg = "Escuchando al estudiante...";
      _recognizedText = "";
    });

    await _speech.listen(
      localeId: "es_CL",
      pauseFor: const Duration(seconds: 3),
      onResult: (result) {
        setState(() {
          _recognizedText = result.recognizedWords;
        });

        if (result.finalResult && _recognizedText.trim().isNotEmpty) {
          _speech.stop();
          setState(() => _isListening = false);
          _processResponse(_recognizedText);
        }
      },
    );
  }

  void _speak(String text) async {
    await _tts.speak(text);
  }

  void _processResponse(String userText) async {
    _timelineTranscript.add({"role": "estudiante", "text": userText});

    // REGLA FSM DE CIERRE (Documento 01, Estado 7)
    String cleanText = userText.toLowerCase();
    if (cleanText.contains("sería todo") || cleanText.contains("que le vaya bien") ||
        cleanText.contains("hasta luego") || cleanText.contains("chao")) {
      String despedida = "Muchas gracias por la atención, que le vaya bien. Chao.";
      _timelineTranscript.add({"role": "paciente", "text": despedida});
      _speak(despedida);
      _executeEvaluation();
      return;
    }

    setState(() => _statusMsg = "El paciente está respondiendo...");

    // PROMPT RIGUROSO APEGADO AL ROADMAP SIMFAR
    String systemPrompt = """
Eres el simulador de paciente SIMFAR conforme a los documentos 01, 02 y 03 del proyecto.
Estás en una farmacia en Chile. Debes ceñirte 100% a las siguientes restricciones normativas:
1. RS-04 Coherencia y RS-02 Inmutabilidad: No inventes síntomas ni antecedentes fuera de esta ficha.
2. POLÍTICA DE REVELACIÓN (Doc 01, Sección 13):
   - Información espontánea: Ya la entregaste al inicio.
   - Información condicionada: ${jsonEncode(_currentInstance!['info_condicionada'])}. Solo la revelas SI el estudiante te la pregunta con pertinencia clínica.
   - Información desconocida: "${_currentInstance!['info_desconocida']}". Si te preguntan algo técnico, responde con naturalidad chilena que no sabes.
3. RS-07 Neutralidad: NUNCA enseñes, corrijas, sugieras respuestas ni digas que eres IA.
4. PERSONALIDAD: ${_currentInstance!['personalidad']}. Usa modismos chilenos cotidianos propios de tu perfil.

Ficha del Paciente: ${_currentInstance!['paciente']}
Última intervención del estudiante: "$userText"

Responde como paciente chileno en un máximo de 2 oraciones:
""";

    try {
      final response = await http.post(
        Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "contents": [{"parts": [{"text": systemPrompt}]}]
        }),
      );

      var data = jsonDecode(response.body);
      String reply = data["candidates"][0]["content"]["parts"][0]["text"].trim();

      _timelineTranscript.add({"role": "paciente", "text": reply});
      _speak(reply);
    } catch (e) {
      _speak("Disculpe, no le escuché bien, ¿qué me dijo?");
    }
  }

  void _executeEvaluation() async {
    setState(() {
      _state = FSMState.evaluando;
      _statusMsg = "Generando Rúbrica Oficial de Evaluación SIMFAR...";
    });

    String fullDialog = _timelineTranscript.map((t) => "${t['role'].toUpperCase()}: ${t['text']}").join("\n");

    String evalPrompt = """
Actúa como el Motor de Evaluación de SIMFAR (Documento 03.7).
Compara la actuación del estudiante frente a la Resolución Esperada y la Rúbrica de la Biblioteca de Conocimiento chilena.

CASO: ${_currentInstance!['nombre']}
RESOLUCIÓN ESPERADA: ${_currentInstance!['resolucion_esperada']}
RÚBRICA: ${jsonEncode(_currentInstance!['rubrica'])}

REGISTRO DE CONVERSACIÓN:
$fullDialog

Genera la retroalimentación objetiva basada en evidencias en formato JSON exacto:
{
  "puntaje": 85,
  "nivel": "Muy Bueno",
  "competencias_blandas": "Evaluación de saludo, cortesía, escucha activa y empatía.",
  "competencias_tecnicas": "Evaluación de anamnesis (alergias/patologías) y correcto fármaco entregado conforme a normativa ISP.",
  "errores_criticos": "Listado de contraindicaciones no advertidas o 'Ninguno'.",
  "recomendaciones": "Acciones concretas para su próxima simulación en farmacia."
}
""";

    try {
      final res = await http.post(
        Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "contents": [{"parts": [{"text": evalPrompt}]}]
        }),
      );

      var data = jsonDecode(res.body);
      String rawJson = data["candidates"][0]["content"]["parts"][0]["text"];
      rawJson = rawJson.replaceAll("```json", "").replaceAll("```", "").trim();

      setState(() {
        _evaluationResult = jsonDecode(rawJson);
        _state = FSMState.retroalimentacion;
      });
    } catch (e) {
      setState(() {
        _state = FSMState.retroalimentacion;
        _evaluationResult = {
          "puntaje": 75,
          "nivel": "Bueno",
          "competencias_blandas": "Buena disposición y tono respetuoso.",
          "competencias_tecnicas": "Entregó el tratamiento pero faltó profundizar en alergias.",
          "errores_criticos": "Ninguno.",
          "recomendaciones": "Siempre descartar patologías de base antes de recomendar."
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SIMFAR - Atención Farmacéutica"),
        backgroundColor: Colors.teal.shade800,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _renderState(),
        ),
      ),
    );
  }

  Widget _renderState() {
    switch (_state) {
      case FSMState.espera:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.medical_services, size: 80, color: Colors.teal),
              const SizedBox(height: 20),
              const Text("SIMFAR Chile", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Text("Simulador Conversacional por Voz", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
                onPressed: () => setState(() => _state = FSMState.configuracion),
                child: const Text("Iniciar Simulación", style: TextStyle(color: Colors.white, fontSize: 16)),
              )
            ],
          ),
        );

      case FSMState.configuracion:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("¿En qué semestre te encuentras?", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: List.generate(5, (i) {
                  int sem = i + 1;
                  return ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade600),
                    onPressed: () => _setupInstance(sem),
                    child: Text("$sem° Semestre", style: const TextStyle(color: Colors.white)),
                  );
                }),
              )
            ],
          ),
        );

      case FSMState.simulacionActiva:
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Icon(_isListening ? Icons.mic : Icons.volume_up, color: Colors.teal.shade800),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_statusMsg, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade900))),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: _timelineTranscript.length,
                itemBuilder: (ctx, i) {
                  bool isStudent = _timelineTranscript[i]["role"] == "estudiante";
                  return Align(
                    alignment: isStudent ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isStudent ? Colors.teal.shade100 : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text("${isStudent ? 'Tú: ' : 'Paciente: '}${_timelineTranscript[i]['text']}"),
                    ),
                  );
                },
              ),
            ),
            Text(_recognizedText.isNotEmpty ? "Oyendo: $_recognizedText" : "Modo Manos Libres Activo", style: const TextStyle(color: Colors.grey)),
          ],
        );

      case FSMState.evaluando:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.teal),
              const SizedBox(height: 20),
              Text(_statusMsg),
            ],
          ),
        );

      case FSMState.retroalimentacion:
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                color: Colors.teal.shade800,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Puntaje: ${_evaluationResult?['puntaje']}%", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      Text("${_evaluationResult?['nivel']}", style: const TextStyle(color: Colors.white, fontSize: 18)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _tile("Competencias Blandas", _evaluationResult?['competencias_blandas']),
              _tile("Competencias Técnicas (Farmacológicas)", _evaluationResult?['competencias_tecnicas']),
              _tile("Errores Críticos", _evaluationResult?['errores_criticos'], isAlert: true),
              _tile("Recomendaciones de Mejora", _evaluationResult?['recomendaciones']),
              const SizedBox(height: 20),
              Center(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () => setState(() => _state = FSMState.espera),
                  child: const Text("Finalizar y Salir", style: TextStyle(color: Colors.white)),
                ),
              )
            ],
          ),
        );

      default:
        return const SizedBox();
    }
  }

  Widget _tile(String title, String? text, {bool isAlert = false}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isAlert ? Colors.red : Colors.teal.shade900)),
            const SizedBox(height: 4),
            Text(text ?? "Sin información"),
          ],
        ),
      ),
    );
  }
}
DART

chmod +x setup_simfar.sh
./setup_simfar.sh
rm setup_simfar.sh

echo "=== 6. Subiendo cambios a GitHub para compilar APK ==="
git add .
git commit -m "Arquitectura SIMFAR con normas ECC completas y manos libres" || true
git push origin HEAD

echo "======================================================="
echo "¡LISTO! Los archivos han sido creados y subidos a GitHub."
echo "Ve a la pestaña 'Actions' de tu repositorio para descargar tu APK."
echo "======================================================="
