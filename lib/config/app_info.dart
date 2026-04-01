/// Classe auxiliar para obter e gerenciar informações globais do aplicativo.
/// 
/// Fornece acesso a informações como versão, nome e data de lançamento do app.
/// Estas informações são carregadas dinamicamente e podem ser acessadas de qualquer lugar do app.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppInfo {
  static String appName = 'Leitor de Etiquetas de Patrimônio';
  static String version = '0.0.0';
  static String buildNumber = '0';
  static String releaseDate = '';
  static bool _initialized = false;
  
  /// Inicializa as informações do app, carregando dados do sistema
  static Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      // Usar package_info_plus para obter informações oficiais do pacote instalado
      final packageInfo = await PackageInfo.fromPlatform();
      
      // Atualizar as informações com os dados oficiais
      appName = packageInfo.appName.isEmpty ? 'Leitor de Etiquetas de Patrimônio' : packageInfo.appName;
      version = packageInfo.version;
      buildNumber = packageInfo.buildNumber;
      
      debugPrint('AppInfo inicializado: $appName v$version+$buildNumber');
      
      // Configurar a data como a data atual (ou poderíamos armazená-la em algum lugar)
      final dateFormat = DateFormat('dd \'de\' MMMM \'de\' yyyy', 'pt_BR');
      releaseDate = dateFormat.format(DateTime.now());
      _initialized = true;
    } catch (e) {
      debugPrint('Erro ao carregar informações do app: $e');
      // Usar os valores padrão em caso de erro
      releaseDate = '7 de maio de 2025';
    }
  }
  
  /// Retorna a versão completa no formato "X.Y.Z (build N)"
  static String getFullVersion() {
    return '$version (build $buildNumber)';
  }
}