import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:install_plugin/install_plugin.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';

class UpdateService {
  // Chaves para preferências
  static const String _prefServerIpKey = "update_server_ip";
  static const String _prefServerPortKey = "update_server_port";
  
  // Dados padrão do servidor de atualização
  static const String _defaultServerIp = "128.1.1.49"; // IP correto do seu servidor
  static const int _defaultServerPort = 8085;
  static const String _apkPath = "apk/barcode.apk";
  static const String _versionEndpoint = "version.json";
  
  // Dados do servidor atual
  String _serverIp = _defaultServerIp;
  int _serverPort = _defaultServerPort;
  
  // URLs completas
  String get _serverUrl => "http://$_serverIp:$_serverPort";
  String get _apkUrl => "$_serverUrl/$_apkPath";
  String get _versionUrl => "$_serverUrl/$_versionEndpoint";
  
  // Configurações avançadas
  final Duration _connectionTimeout = const Duration(seconds: 8);
  final int _connectionRetries = 3;

  // Status da atualização
  bool _isChecking = false;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  
  // Getters para status
  bool get isChecking => _isChecking;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  
  // Getters e setters para configurações
  String get serverIp => _serverIp;
  int get serverPort => _serverPort;
  
  // Atualiza o IP do servidor
  Future<void> setServerIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefServerIpKey, ip);
    _serverIp = ip;
  }
  
  // Atualiza a porta do servidor
  Future<void> setServerPort(int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefServerPortKey, port);
    _serverPort = port;
  }

  // Singleton
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal() {
    _loadSettings();
  }
  
  // Carrega configurações salvas
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _serverIp = prefs.getString(_prefServerIpKey) ?? _defaultServerIp;
      _serverPort = prefs.getInt(_prefServerPortKey) ?? _defaultServerPort;
    } catch (e) {}
  }

  // Método para verificar se há atualizações disponíveis
  Future<UpdateCheckResult> checkForUpdates() async {
    if (_isChecking || _isDownloading) {
      return UpdateCheckResult(
        status: UpdateStatus.inProgress,
        message: 'Operação em andamento',
      );
    }

    _isChecking = true;
    
    try {
      // Verificar conexão com a internet primeiro
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        _isChecking = false;
        return UpdateCheckResult(
          status: UpdateStatus.serverUnavailable,
          message: 'Sem conexão com a internet',
          error: 'Dispositivo sem conexão à rede',
        );
      }
      
      // Obter a versão atual do aplicativo instalado
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = packageInfo.version;
      
      // Verificar se o servidor está online
      bool isServerOnline = false;
      String errorMessage = '';
      
      // Cliente HTTP com configuração específica
      final client = http.Client();
      
      for (int i = 0; i < _connectionRetries; i++) {
        try {
          // Usar reqwest que é mais robusto para ambientes móveis
          final response = await client.get(
            Uri.parse(_serverUrl),
            headers: {'Connection': 'close'}, // Impede problemas de keep-alive
          ).timeout(_connectionTimeout);
          
          if (response.statusCode < 400) {
            isServerOnline = true;
            break;
          } else {
            errorMessage = 'Erro de servidor: ${response.statusCode}';
          }
        } catch (e) {
          errorMessage = e.toString();
          
          // Mostrar mensagem mais amigável para o erro específico
          if (e is SocketException || e.toString().contains('SocketException')) {
            errorMessage = 'Não foi possível conectar ao servidor. Verifique se o dispositivo está na mesma rede do servidor.';
          }
        }
        
        // Pequena pausa entre tentativas
        await Future.delayed(const Duration(milliseconds: 800));
      }
      
      // Fechar o cliente HTTP
      client.close();
      
      if (!isServerOnline) {
        _isChecking = false;
        return UpdateCheckResult(
          status: UpdateStatus.serverUnavailable,
          message: 'Servidor de atualizações não está disponível\nVerifique sua conexão e tente novamente',
          error: errorMessage,
        );
      }
      
      // Tentar buscar informações sobre a versão mais recente
      try {
        // Criar um novo cliente para esta solicitação
        final versionClient = http.Client();
        try {
          final response = await versionClient.get(
            Uri.parse(_versionUrl),
            headers: {'Connection': 'close'},
          ).timeout(_connectionTimeout);
          
          if (response.statusCode == 200) {
            final Map<String, dynamic> versionData = 
                Map<String, dynamic>.from(await _parseJsonOrYaml(response.body));
            
            final String latestVersion = versionData['version'] ?? '0.0.0';
            final String latestBuildNumber = versionData['buildNumber']?.toString() ?? '0';
            
            // Formar a versão completa com o número de build para comparação
            final String latestFullVersion = "$latestVersion+$latestBuildNumber";
            
            // Comparar versões (incluindo o número de build)
            final bool updateAvailable = _isNewerVersion(latestFullVersion, currentVersion + "+" + packageInfo.buildNumber);
            
            _isChecking = false;
            
            if (updateAvailable) {
              return UpdateCheckResult(
                status: UpdateStatus.updateAvailable,
                message: 'Nova versão disponível: $latestVersion (build $latestBuildNumber)',
                latestVersion: latestFullVersion,
              );
            } else {
              return UpdateCheckResult(
                status: UpdateStatus.upToDate,
                message: 'Seu aplicativo está atualizado (versão $currentVersion build ${packageInfo.buildNumber})',
              );
            }
          } else {
            // Se não conseguir obter o arquivo de versão, tenta obter direto do APK
            final bool apkExists = await _doesApkExist();
            
            if (apkExists) {
              _isChecking = false;
              return UpdateCheckResult(
                status: UpdateStatus.updateAvailable,
                message: 'Nova versão disponível',
              );
            } else {
              _isChecking = false;
              return UpdateCheckResult(
                status: UpdateStatus.upToDate,
                message: 'Nenhuma atualização encontrada',
              );
            }
          }
        } finally {
          versionClient.close();
        }
      } catch (e) {
        _isChecking = false;
        return UpdateCheckResult(
          status: UpdateStatus.error,
          message: 'Erro ao verificar atualizações',
          error: e.toString(),
        );
      }
    } catch (e) {
      _isChecking = false;
      return UpdateCheckResult(
        status: UpdateStatus.error,
        message: 'Erro inesperado',
        error: e.toString(),
      );
    }
  }

  // Método para baixar e instalar a atualização
  Future<UpdateResult> downloadAndInstallUpdate({
    required Function(double) onProgress,
  }) async {
    if (_isDownloading) {
      return UpdateResult(
        success: false,
        message: 'Download já está em andamento',
      );
    }

    _isDownloading = true;
    _downloadProgress = 0;
    
    try {
      // Verificar conexão com a internet primeiro
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        _isDownloading = false;
        return UpdateResult(
          success: false,
          message: 'Sem conexão com a internet',
        );
      }
      
      // Verificar e solicitar permissões necessárias
      final bool hasPermission = await _checkAndRequestPermissions();
      if (!hasPermission) {
        _isDownloading = false;
        return UpdateResult(
          success: false,
          message: 'Permissões necessárias não foram concedidas',
        );
      }
      
      // Usar o diretório de Downloads para salvar o APK (mais confiável que o diretório temp)
      Directory? storageDir;
      try {
        if (Platform.isAndroid) {
          // Tenta usar o diretório de downloads que é mais confiável para APKs
          storageDir = await getExternalStorageDirectory();
        }
      } catch (e) {
        // Falha silenciosa, usaremos o diretório temp abaixo
      }
      
      // Se não conseguir o diretório de downloads, usa o temporário
      final Directory saveDir = storageDir ?? await getTemporaryDirectory();
      final String fileName = "etiquetas_patrimonio_update.apk"; // Nome de arquivo fixo para evitar problemas de caracteres especiais
      final String savePath = '${saveDir.path}/$fileName';
      
      // Remover arquivo antigo se existir
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }
      
      // Criar instância do Dio para download com progresso
      final Dio dio = Dio();
      dio.options.connectTimeout = _connectionTimeout;
      dio.options.receiveTimeout = const Duration(minutes: 5);
      dio.options.headers = {'Connection': 'close'};
      
      try {
        await dio.download(
          _apkUrl,
          savePath,
          deleteOnError: true, // Apaga o arquivo se houver erro no download
          onReceiveProgress: (received, total) {
            if (total != -1) {
              _downloadProgress = received / total;
              onProgress(_downloadProgress);
            }
          },
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            validateStatus: (status) {
              return status != null && status < 500;
            },
          ),
        );
        
        // Verificar se o download foi concluído corretamente
        if (!await file.exists()) {
          _isDownloading = false;
          return UpdateResult(
            success: false,
            message: 'Erro ao salvar o arquivo de atualização',
            error: 'Arquivo não encontrado após download',
          );
        }
        
        // Verificar tamanho do arquivo
        final int fileSize = await file.length();
        if (fileSize < 1024 * 1024) { // Menor que 1MB
          _isDownloading = false;
          return UpdateResult(
            success: false,
            message: 'Arquivo de instalação inválido',
            error: 'Tamanho do APK muito pequeno: $fileSize bytes',
          );
        }
      } catch (e) {
        _isDownloading = false;
        
        String errorMsg = 'Erro ao baixar atualização';
        if (e is DioException) {
          if (e.type == DioExceptionType.connectionTimeout) {
            errorMsg = 'Tempo esgotado ao tentar conectar com o servidor';
          } else if (e.type == DioExceptionType.receiveTimeout) {
            errorMsg = 'Tempo esgotado ao receber dados do servidor';
          }
        }
        
        return UpdateResult(
          success: false,
          message: errorMsg,
          error: e.toString(),
        );
      }
      
      // Após o download, instalar o APK
      final result = await _installApk(savePath);
      _isDownloading = false;
      
      return result;
    } catch (e) {
      _isDownloading = false;
      return UpdateResult(
        success: false,
        message: 'Erro ao baixar ou instalar atualização',
        error: e.toString(),
      );
    }
  }
  
  // Verifica se o servidor está disponível
  Future<bool> _isServerAvailable() async {
    try {
      final client = http.Client();
      try {
        final response = await client.get(
          Uri.parse(_serverUrl),
          headers: {'Connection': 'close'},
        ).timeout(_connectionTimeout);
        
        final bool isAvailable = response.statusCode < 400;
        return isAvailable;
      } finally {
        client.close();
      }
    } catch (e) {
      return false;
    }
  }
  
  // Verifica se o APK existe no servidor
  Future<bool> _doesApkExist() async {
    try {
      final client = http.Client();
      try {
        final response = await client.head(
          Uri.parse(_apkUrl),
          headers: {'Connection': 'close'},
        ).timeout(_connectionTimeout);
        
        final bool exists = response.statusCode < 400;
        return exists;
      } finally {
        client.close();
      }
    } catch (e) {
      return false;
    }
  }
  
  // Verifica se uma versão é diferente da atual (permitindo upgrade ou downgrade)
  bool _isNewerVersion(String serverVersion, String currentVersion) {
    // Se as versões são completamente diferentes (incluindo o build number), considerar como uma atualização
    if (serverVersion != currentVersion) {
      final bool isUpgrade = _compareVersionValues(serverVersion, currentVersion) > 0;
      // Sempre retorna true quando as versões são diferentes, permitindo tanto upgrade quanto downgrade
      return true;
    }
    
    return false;
  }
  
  // Auxiliar para comparar valores de versão (apenas para fins informativos no log)
  // Retorna: 1 se v1 > v2, -1 se v1 < v2, 0 se iguais
  int _compareVersionValues(String v1, String v2) {
    final String cleanV1 = v1.split('+').first;
    final String cleanV2 = v2.split('+').first;
    
    final List<int> parts1 = cleanV1.split('.')
        .map((part) => int.tryParse(part) ?? 0).toList();
    final List<int> parts2 = cleanV2.split('.')
        .map((part) => int.tryParse(part) ?? 0).toList();
    
    // Garantir que ambas as listas têm pelo menos 3 elementos
    while (parts1.length < 3) parts1.add(0);
    while (parts2.length < 3) parts2.add(0);
    
    // Comparar versão por componente
    for (int i = 0; i < 3; i++) {
      if (parts1[i] > parts2[i]) return 1;
      if (parts1[i] < parts2[i]) return -1;
    }
    
    // Se as versões semânticas são iguais, comparar build numbers
    final int build1 = int.tryParse(v1.contains('+') ? v1.split('+').last : '0') ?? 0;
    final int build2 = int.tryParse(v2.contains('+') ? v2.split('+').last : '0') ?? 0;
    
    if (build1 > build2) return 1;
    if (build1 < build2) return -1;
    
    return 0;
  }
  
  // Verifica e solicita permissões necessárias
  Future<bool> _checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      // No Android 13+, precisamos de permissão para instalar pacotes
      if (await Permission.requestInstallPackages.request().isGranted) {
        return true;
      }
      
      // No Android mais antigo, verificamos permissão de armazenamento
      if (await Permission.storage.request().isGranted) {
        return true;
      }
      
      return false;
    }
    
    // Em outras plataformas, assumimos que temos permissão
    return true;
  }
  
  // Instala o APK baixado
  Future<UpdateResult> _installApk(String filePath) async {
    try {
      if (Platform.isAndroid) {
        // Verificar se o arquivo existe
        final file = File(filePath);
        if (!await file.exists()) {
          return UpdateResult(
            success: false,
            message: 'Arquivo de instalação não encontrado',
            error: 'APK não existe no caminho especificado',
          );
        }
        
        // Verificar tamanho do arquivo (deve ser maior que 1MB para ser um APK válido)
        final fileSize = await file.length();
        if (fileSize < 1024 * 1024) {
          return UpdateResult(
            success: false,
            message: 'Arquivo de instalação inválido',
            error: 'Tamanho do APK muito pequeno',
          );
        }

        // Estratégia 1: InstallPlugin (versão simples compatível com a biblioteca)
        try {
          // A biblioteca install_plugin na versão atual só aceita um argumento
          await InstallPlugin.installApk(filePath);
          
          await Future.delayed(const Duration(milliseconds: 500));
          return UpdateResult(
            success: true,
            message: 'Instalação iniciada',
          );
        } catch (e) {
          // Se a estratégia 1 falhar, tentamos a estratégia 2
        }

        // Estratégia 2: OpenFilex com configurações básicas
        try {
          final result = await OpenFilex.open(
            filePath,
            type: 'application/vnd.android.package-archive',
            uti: 'public.android-package-archive',
            // Removido o parâmetro forceOpenWith que não é suportado
          );
          
          if (result.type == ResultType.done) {
            await Future.delayed(const Duration(milliseconds: 500));
            return UpdateResult(
              success: true,
              message: 'Instalação iniciada',
            );
          } else {
            throw Exception(result.message);
          }
        } catch (e) {
          // Se a estratégia 2 falhar, tentamos a estratégia 3
        }

        // Estratégia 3: Método simplificado - última tentativa
        try {
          final result = await OpenFilex.open(filePath);
          if (result.type == ResultType.done) {
            return UpdateResult(
              success: true,
              message: 'Instalação iniciada',
            );
          } else {
            throw Exception(result.message);
          }
        } catch (e) {
          return UpdateResult(
            success: false,
            message: 'Não foi possível iniciar a instalação',
            error: e.toString(),
          );
        }
      } else {
        // Em outras plataformas, tentamos abrir o arquivo
        final result = await OpenFilex.open(filePath);
        
        return UpdateResult(
          success: result.type == ResultType.done,
          message: result.type == ResultType.done 
              ? 'Instalação iniciada' 
              : 'Não foi possível iniciar a instalação',
          error: result.type != ResultType.done ? result.message : null,
        );
      }
    } catch (e) {
      return UpdateResult(
        success: false,
        message: 'Erro ao instalar o APK',
        error: e.toString(),
      );
    }
  }
  
  // Tenta analisar JSON ou YAML
  Future<dynamic> _parseJsonOrYaml(String content) async {
    try {
      // Tentar parse como JSON
      return json.decode(content);
    } catch (e) {
      try {
        // Se falhar, tentar como YAML
        return loadYaml(content);
      } catch (e) {
        // Se ambos falharem, retornar um mapa vazio
        return {};
      }
    }
  }
}

// Classes para representar resultados
class UpdateCheckResult {
  final UpdateStatus status;
  final String message;
  final String? latestVersion;
  final String? error;
  
  UpdateCheckResult({
    required this.status,
    required this.message,
    this.latestVersion,
    this.error,
  });
}

class UpdateResult {
  final bool success;
  final String message;
  final String? error;
  
  UpdateResult({
    required this.success,
    required this.message,
    this.error,
  });
}

// Enum para status da atualização
enum UpdateStatus {
  updateAvailable,
  upToDate,
  serverUnavailable,
  error,
  inProgress
}