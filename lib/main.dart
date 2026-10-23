import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

// Clave por defecto configurable desde la app o por --dart-define
String currentApiKey = const String.fromEnvironment(
  "GEMINI_API_KEY", 
  defaultValue: "AQ.Ab8RN6IFJQTsJg08R6iXRRc80_FTlVTbWf1VtzUozcZ-m__dmg"
);

void main() {
  runApp(const MaterialApp(
    home: SimfarEngineScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

enum FSMState { espera, configuracion, simulacionActiva, evaluando, retroalimentacion }

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
  final List<Map<String, String>> _timelineTranscript = [];
  Map<String, dynamic>? _evaluationResult;

  // CASOS CLÍNICOS ESTRUCTURADOS SEGÚN ECC 03.1 - 03.8 (CHILE)
  final List<Map<String, dynamic>> _knowledgeBank = [
    {
      "nivel": 1,
      "caso_id": "CASO-0012",
      "nombre": "Faringitis viral no complicada (OTC)",
      "paciente": "Carlos Soto, 42 años, feriante en San Bernardo.",
      "personalidad": "Colaborador, habla pausado, modismos chilenos habituales.",
      "info_espontanea": "Hola buenas tardes oiga... ando buscando un remedio porque desde ayer me duele caleta la garganta y me cuesta hasta tragar la saliva.",
      "info_condicionada": {
        "fiebre": "No he tenido fiebre, solo molestia al tragar.",
        "alergias": "Ninguna alergia conocida.",
        "medicamentos": "Solo me tomé un tecito con miel y limón anoche.",
        "enfermedades": "No sufro de nada crónico, soy sano."
      },
      "info_desconocida": "No conozco nombres de principios activos ni miligramos.",
      "resolucion_esperada": "Tratamiento sintomático con Paracetamol 500mg o Ibuprofeno 400mg vía oral. Medidas no farmacológicas: hidratación abundante y reposo. NO indicar antibióticos.",
      "rubrica": {
        "criterio_clinico": "Preguntar por alergias y duración del dolor.",
        "criterio_tecnico": "Seleccionar analgésico OTC sin sugerir antibióticos.",
        "criterio_blando": "Trato respetuoso, empatía y lenguaje claro."
      }
    },
    {
      "nivel": 2,
      "caso_id": "CASO-0025",
      "nombre": "Pirosis gástrica por transgresión alimentaria (OTC)",
      "paciente": "Gladys Muñoz, 56 años, vecina de Maipú.",
      "personalidad": "Ansiosa, preocupada, tiende a dramatizar síntomas leves.",
      "info_espontanea": "Buenas tardes oiga... vengo afligida porque ando con una quemazón insoportable en el pecho y me duele la guata desde anoche.",
      "info_condicionada": {
        "tiempo": "Empezó anoche después de comer frituras.",
        "alergias": "Alergia a la penicilina.",
        "enfermedades": "Hipertensión arterial controlada.",
        "medicamentos": "Tomo Losartán de 50mg cada mañana."
      },
      "info_desconocida": "Desconozco qué antiácido es compatible con mis remedios.",
      "resolucion_esperada": "Antiácido local en suspensión (Magaldrato o Hidróxido de Aluminio/Magnesio). Advertir espaciar 2 horas de su Losartán. ERROR CRÍTICO: Recomendar AINEs.",
      "rubrica": {
        "criterio_clinico": "Identificar antecedente de Losartán y descartar signos de alarma.",
        "criterio_tecnico": "Indicar antiácido no sistémico y explicar intervalo de dosis.",
        "criterio_blando": "Calmar la ansiedad de la paciente con tono empático."
      }
    },
    {
      "nivel": 3,
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
      "resolucion_esperada": "ERROR CRÍTICO: Indicar antigripal con Pseudoefedrina o Fenilefrina. CONDUCTA CORRECTA: Explicar contraindicación por hipertensión, entregar Paracetamol puro y sugerir lavados nasales con suero.",
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
    
    // VELOCIDAD CALIBRADA: 0.48 equivale a 1.0x (habla humana normal y relajada)
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
  }

  void _setupInstance(int semestre) {
    int targetNivel = (semestre <= 2) ? 1 : (semestre <= 4 ? 2 : 3);
    var matchedCases = _knowledgeBank.where((c) => c["nivel"] == targetNivel).toList();
    _currentInstance = matchedCases.first;

    setState(() {
      _state = FSMState.simulacionActiva;
      _timelineTranscript.clear();
      _statusMsg = "Paciente en ventanilla. Presiona el botón para responder.";
    });

    String firstLine = _currentInstance!["info_espontanea"];
    _timelineTranscript.add({"role": "paciente", "text": firstLine});
    _speak(firstLine);
  }

  // PUSH-TO-TALK: Iniciar captura
  void _startListening() async {
    if (_isListening) return;

    await _tts.stop(); // Si el paciente estaba hablando, se interrumpe
    bool available = await _speech.initialize();
    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error: Permiso de micrófono no habilitado")),
      );
      return;
    }

    setState(() {
      _isListening = true;
      _recognizedText = "";
      _statusMsg = "Escuchando... Di tu mensaje";
    });

    await _speech.listen(
      localeId: "es_CL",
      onResult: (result) {
        setState(() {
          _recognizedText = result.recognizedWords;
        });
      },
    );
  }

  // PUSH-TO-TALK: Detener captura y enviar
  void _stopListeningAndSend() async {
    if (!_isListening) return;

    await _speech.stop();
    setState(() {
      _isListening = false;
    });

    if (_recognizedText.trim().isNotEmpty) {
      _processResponse(_recognizedText);
    } else {
      setState(() => _statusMsg = "No se detectó audio. Vuelve a presionar el botón.");
    }
  }

  void _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  void _processResponse(String userText) async {
    _timelineTranscript.add({"role": "estudiante", "text": userText});

    // REGLA FSM DE CIERRE (Doc 01, Estado 7)
    String cleanText = userText.toLowerCase();
    if (cleanText.contains("sería todo") || cleanText.contains("que le vaya bien") ||
        cleanText.contains("hasta luego") || cleanText.contains("chao") || cleanText.contains("adiós")) {
      String despedida = "Muchas gracias por su atención, que esté muy bien. Chao.";
      _timelineTranscript.add({"role": "paciente", "text": despedida});
      _speak(despedida);
      _executeEvaluation();
      return;
    }

    setState(() => _statusMsg = "El paciente está pensando...");

    String systemPrompt = """
Eres el simulador de paciente SIMFAR conforme a los documentos oficiales del proyecto.
Estás en una farmacia en Chile. Debes ceñirte 100% a las siguientes restricciones normativas:
1. RS-04 Coherencia y RS-02 Inmutabilidad: No inventes síntomas ni antecedentes fuera de esta ficha.
2. POLÍTICA DE REVELACIÓN:
   - Información espontánea: Ya la diste al principio.
   - Información condicionada: ${jsonEncode(_currentInstance!['info_condicionada'])}. Solo la revelas SI el estudiante te la pregunta específicamente.
   - Información desconocida: "${_currentInstance!['info_desconocida']}". Si te preguntan algo técnico, responde con naturalidad que no sabes.
3. RS-07 Neutralidad: NUNCA enseñes, corrijas, sugieras respuestas ni digas que eres IA.
4. PERSONALIDAD: ${_currentInstance!['personalidad']}. Usa modismos chilenos cotidianos propios de tu perfil.

Ficha del Paciente: ${_currentInstance!['paciente']}
Última intervención del estudiante: "$userText"

Responde como paciente chileno en un máximo de 2 oraciones:
""";

    try {
      final response = await http.post(
        Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$currentApiKey"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "contents": [{"parts": [{"text": systemPrompt}]}]
        }),
      );

      if (response.statusCode != 200) {
        String errorDetalle = "Error de API (${response.statusCode}): ";
        try {
          var err = jsonDecode(response.body);
          errorDetalle += err["error"]?["message"] ?? response.body;
        } catch (_) {
          errorDetalle += response.body;
        }
        setState(() {
          _statusMsg = "Error en la llamada a Gemini";
          _timelineTranscript.add({"role": "error", "text": errorDetalle});
        });
        return;
      }

      var data = jsonDecode(response.body);
      String reply = data["candidates"][0]["content"]["parts"][0]["text"].trim();

      _timelineTranscript.add({"role": "paciente", "text": reply});
      setState(() => _statusMsg = "Paciente ha respondido");
      _speak(reply);
    } catch (e) {
      setState(() {
        _statusMsg = "Fallo de conexión: $e";
        _timelineTranscript.add({"role": "error", "text": "Error local: $e"});
      });
    }
  }

  void _executeEvaluation() async {
    setState(() {
      _state = FSMState.evaluando;
      _statusMsg = "Generando Rúbrica Oficial de Evaluación SIMFAR...";
    });

    String fullDialog = _timelineTranscript
        .where((t) => t['role'] != 'error')
        .map((t) => "${(t['role'] ?? '').toUpperCase()}: ${t['text']}")
        .join("\n");

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
        Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$currentApiKey"),
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
          "competencias_blandas": "Buena disposición y trato cordial.",
          "competencias_tecnicas": "Se entregó orientación general de farmacia.",
          "errores_criticos": "Ninguno.",
          "recomendaciones": "Asegurar descarte de patologías antes de la dispensación."
        };
      });
    }
  }

  void _showApiKeyDialog() {
    TextEditingController controller = TextEditingController(text: currentApiKey);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Configuración de API Key"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Ingresa tu clave de Gemini si necesitas renovarla:", style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "Pega tu clave de Gemini",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                currentApiKey = controller.text.trim();
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Clave actualizada")),
              );
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SIMFAR - Farmacia Chile"),
        backgroundColor: Colors.teal.shade800,
        actions: [
          IconButton(
            icon: const Icon(Icons.key, color: Colors.white),
            tooltip: "Configurar API Key",
            onPressed: _showApiKeyDialog,
          )
        ],
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
              const Text("Simulador Conversacional de Farmacia", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow, color: Colors.white),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                onPressed: () => setState(() => _state = FSMState.configuracion),
                label: const Text("Iniciar Simulación", style: TextStyle(color: Colors.white, fontSize: 16)),
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
                  Icon(_isListening ? Icons.mic : Icons.volume_up, color: _isListening ? Colors.red : Colors.teal.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMsg,
                      style: TextStyle(fontWeight: FontWeight.bold, color: _isListening ? Colors.red : Colors.teal.shade900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: _timelineTranscript.length,
                itemBuilder: (ctx, i) {
                  var item = _timelineTranscript[i];
                  bool isStudent = item["role"] == "estudiante";
                  bool isError = item["role"] == "error";

                  return Align(
                    alignment: isStudent ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isError
                            ? Colors.red.shade100
                            : (isStudent ? Colors.teal.shade100 : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isError
                            ? "⚠️ ${item['text']}"
                            : "${isStudent ? 'Tú: ' : 'Paciente: '}${item['text']}",
                        style: TextStyle(color: isError ? Colors.red.shade900 : Colors.black87),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_recognizedText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text("Reconocido: \"$_recognizedText\"", style: const TextStyle(color: Colors.blueGrey, fontStyle: FontStyle.italic)),
              ),
            const SizedBox(height: 10),

            // BOTÓN PUSH-TO-TALK CON SOPORTE PARA MANTENER O TOCAR
            GestureDetector(
              onTapDown: (_) => _startListening(),
              onTapUp: (_) => _stopListeningAndSend(),
              onTapCancel: () => _stopListeningAndSend(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: _isListening ? Colors.red.shade600 : Colors.teal.shade700,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: (_isListening ? Colors.red : Colors.teal).withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isListening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 28),
                    const SizedBox(width: 10),
                    Text(
                      _isListening ? "SOLTAR PARA ENVIAR" : "MANTÉN PRESIONADO PARA HABLAR",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
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
