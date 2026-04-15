// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appName => 'AnySkill';

  @override
  String get appSlogan => 'Tus profesionales, a un toque';

  @override
  String get greetingMorning => 'Buenos Días';

  @override
  String get greetingAfternoon => 'Buenas Tardes';

  @override
  String get greetingEvening => 'Buenas Noches';

  @override
  String get greetingNight => 'Buenas Noches';

  @override
  String get greetingSubMorning => '¿Qué te gustaría hacer hoy?';

  @override
  String get greetingSubAfternoon => '¿Necesitas ayuda con algo?';

  @override
  String get greetingSubEvening => '¿Sigues buscando un servicio?';

  @override
  String get greetingSubNight => '¡Nos vemos mañana!';

  @override
  String get tabHome => 'Inicio';

  @override
  String get tabBookings => 'Reservas';

  @override
  String get tabChat => 'Mensajes';

  @override
  String get tabWallet => 'Cartera';

  @override
  String get bookNow => 'Reservar Ahora';

  @override
  String get bookingCompleted => 'Reserva completada exitosamente';

  @override
  String get close => 'Cerrar';

  @override
  String get retryButton => 'Reintentar';

  @override
  String get saveChanges => 'Guardar Cambios';

  @override
  String get saveSuccess => 'Guardado exitosamente';

  @override
  String saveError(String error) {
    return 'Error al guardar: $error';
  }

  @override
  String get defaultUserName => 'Usuario';

  @override
  String get notLoggedIn => 'No conectado';

  @override
  String get linkCopied => 'Enlace copiado';

  @override
  String get errorEmptyFields => 'Por favor completa todos los campos';

  @override
  String get errorGeneric => 'Ocurrió un error. Inténtalo de nuevo';

  @override
  String get errorInvalidEmail => 'Dirección de correo no válida';

  @override
  String get whatsappError => 'No se puede abrir WhatsApp';

  @override
  String get markAllReadTooltip => 'Marcar todo como leído';

  @override
  String get onlineStatus => 'Disponible';

  @override
  String get offlineStatus => 'No Disponible';

  @override
  String get onlineToggleOn => 'Ahora estás disponible';

  @override
  String get onlineToggleOff => 'Ahora no estás disponible';

  @override
  String get roleCustomer => 'Cliente';

  @override
  String get roleProvider => 'Proveedor de Servicios';

  @override
  String get loginAccountTitle => 'Inicio de sesión';

  @override
  String get loginButton => 'Entrar';

  @override
  String get loginEmail => 'Correo electrónico';

  @override
  String get loginForgotPassword => '¿Olvidaste tu contraseña?';

  @override
  String get loginNoAccount => '¿No tienes cuenta? ';

  @override
  String get loginPassword => 'Contraseña';

  @override
  String get loginRememberMe => 'Recuérdame';

  @override
  String get loginSignUpFree => 'Regístrate gratis';

  @override
  String get loginStats10k => '10K+';

  @override
  String get loginStats50 => '50+';

  @override
  String get loginStats49 => '4.9★';

  @override
  String get loginWelcomeBack => '¡Bienvenido de vuelta!';

  @override
  String get signupAccountCreated => '¡Cuenta creada exitosamente!';

  @override
  String get signupEmailInUse => 'El correo ya está en uso';

  @override
  String get signupGenericError => 'Ocurrió un error durante el registro';

  @override
  String get signupGoogleError => 'Error al iniciar sesión con Google';

  @override
  String get signupNetworkError => 'Error de red. Verifica tu conexión';

  @override
  String get signupNewCustomerBio => 'Nuevo cliente en AnySkill';

  @override
  String get signupNewProviderBio => 'Nuevo proveedor en AnySkill';

  @override
  String get signupTosMustAgree => 'Debes aceptar los Términos de Servicio';

  @override
  String get signupWeakPassword => 'La contraseña es muy débil';

  @override
  String get forgotPasswordEmail => 'Correo electrónico';

  @override
  String get forgotPasswordError => 'Error al enviar enlace de restablecimiento';

  @override
  String get forgotPasswordSubmit => 'Enviar Enlace';

  @override
  String get forgotPasswordSubtitle => 'Ingresa tu correo y te enviaremos un enlace para restablecer tu contraseña';

  @override
  String get forgotPasswordSuccess => 'Enlace de restablecimiento enviado a tu correo';

  @override
  String get forgotPasswordTitle => 'Olvidé mi Contraseña';

  @override
  String authError(String code) {
    return 'Error de autenticación: $code';
  }

  @override
  String get profileTitle => 'Mi Perfil';

  @override
  String get profileFieldName => 'Nombre Completo';

  @override
  String get profileFieldNameHint => 'Ingresa tu nombre completo';

  @override
  String get profileFieldRole => 'Tipo de Usuario';

  @override
  String get profileFieldCategoryMain => 'Categoría Principal';

  @override
  String get profileFieldCategoryMainHint => 'Elige tu categoría principal';

  @override
  String get profileFieldCategorySub => 'Sub-Categoría';

  @override
  String get profileFieldCategorySubHint => 'Elige una especialidad específica';

  @override
  String get profileFieldPrice => 'Precio por Hora (₪)';

  @override
  String get profileFieldPriceHint => 'Ingresa tu tarifa por hora';

  @override
  String get profileFieldResponseTime => 'Tiempo de Respuesta (minutos)';

  @override
  String get profileFieldResponseTimeHint => 'Tiempo de respuesta promedio';

  @override
  String get profileFieldTaxId => 'Número de Licencia Comercial';

  @override
  String get profileFieldTaxIdHint => 'Ingresa número de licencia';

  @override
  String get profileFieldTaxIdHelp => 'Este número se usará para facturación';

  @override
  String get editProfileAbout => 'Sobre Mí';

  @override
  String get editProfileAboutHint => 'Cuéntales a los clientes sobre tu experiencia...';

  @override
  String get editProfileCancellationPolicy => 'Política de Cancelación';

  @override
  String get editProfileCancellationHint => 'Elige una política de cancelación';

  @override
  String get editProfileGallery => 'Galería';

  @override
  String get editProfileQuickTags => 'Etiquetas Rápidas';

  @override
  String get editProfileTagsHint => 'Agrega etiquetas a tu perfil';

  @override
  String editProfileTagsSelected(int count) {
    return '$count seleccionados';
  }

  @override
  String get editCategoryTitle => 'Editar Categoría';

  @override
  String get editCategoryNameLabel => 'Nombre de Categoría';

  @override
  String get editCategoryChangePic => 'Cambiar Imagen';

  @override
  String get shareProfileTitle => 'Compartir Perfil';

  @override
  String get shareProfileTooltip => 'Comparte tu perfil';

  @override
  String get shareProfileCopyLink => 'Copiar Enlace';

  @override
  String get shareProfileWhatsapp => 'Compartir en WhatsApp';

  @override
  String get statBalance => 'Saldo';

  @override
  String get searchHintExperts => 'Buscar profesionales...';

  @override
  String get searchDefaultTitle => 'Buscar';

  @override
  String get searchDefaultCity => 'Israel';

  @override
  String get searchDefaultExpert => 'Profesional';

  @override
  String get searchSectionCategories => 'Categorías';

  @override
  String searchSectionResultsFor(String query) {
    return 'Resultados para \"$query\"';
  }

  @override
  String searchNoResultsFor(String query) {
    return 'Sin resultados para \"$query\"';
  }

  @override
  String get searchNoCategoriesBody => 'No se encontraron categorías';

  @override
  String get searchPerHour => '₪/hora';

  @override
  String get searchRecommendedBadge => 'Recomendado';

  @override
  String get searchChipHomeVisit => 'Visita a Domicilio';

  @override
  String get searchChipWeekend => 'Disponible Fines de Semana';

  @override
  String get searchDatePickerHint => 'Selecciona una fecha';

  @override
  String get searchTourSearchTitle => 'Buscar Profesionales';

  @override
  String get searchTourSearchDesc => 'Busca por nombre, servicio o categoría';

  @override
  String get searchTourSuggestionsTitle => 'Sugerencias Inteligentes';

  @override
  String get searchTourSuggestionsDesc => 'Sugerencias personalizadas basadas en tus búsquedas';

  @override
  String get searchUrgencyMorning => 'Mañana';

  @override
  String get searchUrgencyAfternoon => 'Tarde';

  @override
  String get searchUrgencyEvening => 'Noche';

  @override
  String get catResultsSearchHint => 'Buscar en la categoría...';

  @override
  String catResultsNoExperts(String category) {
    return 'No hay profesionales en $category';
  }

  @override
  String get catResultsNoResults => 'Sin resultados';

  @override
  String get catResultsNoResultsHint => 'Intenta cambiar tu búsqueda';

  @override
  String get catResultsPerHour => '₪/hora';

  @override
  String catResultsOrderCount(int count) {
    return '$count pedidos';
  }

  @override
  String catResultsResponseTime(int minutes) {
    return 'Responde en $minutes min';
  }

  @override
  String get catResultsRecommended => 'Recomendado';

  @override
  String get catResultsTopRated => 'Mejor Calificado';

  @override
  String get catResultsUnder100 => 'Menos de ₪100';

  @override
  String get catResultsClearFilters => 'Limpiar Filtros';

  @override
  String get catResultsBeFirst => '¡Sé el primero!';

  @override
  String get catResultsExpertDefault => 'Profesional';

  @override
  String get catResultsLoadMore => 'Cargar Más';

  @override
  String get catResultsAvailableSlots => 'Horarios Disponibles';

  @override
  String get catResultsNoAvailability => 'Sin Disponibilidad';

  @override
  String get catResultsFullBooking => 'Completo';

  @override
  String get catResultsWhenFree => '¿Cuándo disponible?';

  @override
  String get chatListTitle => 'Mensajes';

  @override
  String get expertSectionAbout => 'Acerca de';

  @override
  String get expertSectionService => 'Servicio';

  @override
  String get expertSectionSchedule => 'Disponibilidad';

  @override
  String get expertBioPlaceholder => 'Sin biografía aún';

  @override
  String get expertBioReadMore => 'Leer más';

  @override
  String get expertBioShowLess => 'Mostrar menos';

  @override
  String get expertNoReviews => 'Sin reseñas aún';

  @override
  String get expertDefaultReviewer => 'Usuario';

  @override
  String get expertProviderResponse => 'Respuesta del proveedor';

  @override
  String get expertAddReply => 'Agregar respuesta';

  @override
  String get expertAddReplyTitle => 'Agregar respuesta a la reseña';

  @override
  String get expertReplyHint => 'Escribe una respuesta...';

  @override
  String get expertPublishReply => 'Publicar respuesta';

  @override
  String get expertReplyError => 'Error al publicar respuesta';

  @override
  String get expertSelectDateTime => 'Selecciona fecha y hora';

  @override
  String get expertSelectTime => 'Selecciona hora';

  @override
  String expertBookForTime(String time) {
    return 'Reservar para $time';
  }

  @override
  String expertStartingFrom(String price) {
    return 'Desde ₪$price';
  }

  @override
  String get expertBookingSummaryTitle => 'Resumen de Reserva';

  @override
  String get expertSummaryRowService => 'Servicio';

  @override
  String get expertSummaryRowDate => 'Fecha';

  @override
  String get expertSummaryRowTime => 'Hora';

  @override
  String get expertSummaryRowPrice => 'Precio';

  @override
  String get expertSummaryRowIncluded => 'Incluido';

  @override
  String get expertSummaryRowProtection => 'Protección al Comprador';

  @override
  String get expertSummaryRowTotal => 'Total';

  @override
  String get expertConfirmPaymentButton => 'Confirmar y Pagar';

  @override
  String get expertVerifiedBooking => 'Reserva Verificada';

  @override
  String get expertInsufficientBalance => 'Saldo insuficiente';

  @override
  String get expertEscrowSuccess => 'Pago confirmado y protegido hasta finalizar la transacción';

  @override
  String expertTransactionTitle(String name) {
    return 'Pago a $name';
  }

  @override
  String expertSystemMessage(String date, String time, String amount) {
    return 'Reserva confirmada para $date a las $time. ₪$amount asegurados en depósito.';
  }

  @override
  String expertCancellationNotice(String policy, String deadline, String penalty) {
    return 'Política $policy: Cancelación gratuita hasta $deadline. Después $penalty% de penalización.';
  }

  @override
  String expertCancellationNoDeadline(String policy, String description) {
    return 'Política $policy: $description';
  }

  @override
  String get financeTitle => 'Finanzas';

  @override
  String get financeAvailableBalance => 'Saldo Disponible';

  @override
  String get financePending => 'Pendiente';

  @override
  String get financeProcessing => 'Procesando';

  @override
  String get financeRecentActivity => 'Actividad Reciente';

  @override
  String get financeNoTransactions => 'Sin transacciones';

  @override
  String get financeWithdrawButton => 'Retirar Fondos';

  @override
  String get financeMinWithdraw => 'Retiro mínimo: ₪50';

  @override
  String get financeTrustBadge => 'Tu dinero está protegido';

  @override
  String financeReceivedFrom(String name) {
    return 'Recibido de $name';
  }

  @override
  String financePaidTo(String name) {
    return 'Pagado a $name';
  }

  @override
  String financeError(String error) {
    return 'Error: $error';
  }

  @override
  String get disputeConfirmRefund => 'Confirmar Reembolso';

  @override
  String get disputeConfirmRelease => 'Confirmar Liberación de Pago';

  @override
  String get disputeConfirmSplit => 'Confirmar División';

  @override
  String get disputePartyCustomer => 'el cliente';

  @override
  String disputeRefundBody(String amount, String customerName) {
    return '₪$amount serán reembolsados a $customerName';
  }

  @override
  String disputeReleaseBody(String netAmount, String expertName, String feePercent) {
    return '₪$netAmount serán liberados a $expertName (comisión $feePercent%)';
  }

  @override
  String disputeSplitBody(String halfAmount, String halfNet, String platformFee) {
    return 'División: ₪$halfAmount por lado. Proveedor recibe ₪$halfNet, plataforma ₪$platformFee';
  }

  @override
  String get disputeResolvedRefund => 'Disputa resuelta — reembolso emitido';

  @override
  String get disputeResolvedRelease => 'Disputa resuelta — pago liberado';

  @override
  String get disputeResolvedSplit => 'Disputa resuelta — monto dividido';

  @override
  String get disputeTypeAudio => 'Audio';

  @override
  String get disputeTypeImage => 'Imagen';

  @override
  String get disputeTypeLocation => 'Ubicación';

  @override
  String get releasePaymentError => 'Error al liberar el pago';

  @override
  String get oppTitle => 'Oportunidades';

  @override
  String get oppAllCategories => 'Todas las Categorías';

  @override
  String get oppEmptyAll => 'No hay oportunidades ahora';

  @override
  String get oppEmptyAllSubtitle => 'Vuelve más tarde';

  @override
  String get oppEmptyCategory => 'No hay oportunidades en esta categoría';

  @override
  String get oppEmptyCategorySubtitle => 'Prueba otra categoría';

  @override
  String get oppTakeOpportunity => 'Tomar Oportunidad';

  @override
  String get oppInterested => 'Interesado';

  @override
  String get oppAlreadyInterested => 'Ya expresaste interés';

  @override
  String get oppAlreadyExpressed => 'Ya expresaste interés en esta solicitud';

  @override
  String get oppAlready3Interested => 'Ya hay 3 interesados';

  @override
  String get oppInterestSuccess => '¡Tu interés ha sido registrado!';

  @override
  String get oppRequestClosed3 => 'Solicitud cerrada — 3 interesados';

  @override
  String get oppRequestClosedBtn => 'Solicitud Cerrada';

  @override
  String get oppRequestUnavailable => 'La solicitud ya no está disponible';

  @override
  String get oppDefaultClient => 'Cliente';

  @override
  String get oppHighDemand => 'Alta Demanda';

  @override
  String get oppQuickBid => 'Oferta Rápida';

  @override
  String oppQuickBidMessage(String clientName, String providerName) {
    return 'Hola $clientName, soy $providerName y me encantaría ayudar.';
  }

  @override
  String get oppEstimatedEarnings => 'Ganancias Estimadas';

  @override
  String get oppAfterFee => 'Después de comisión';

  @override
  String get oppWalletHint => 'Las ganancias van a tu cartera';

  @override
  String oppXpToNextLevel(int xpNeeded, String levelName) {
    return '$xpNeeded XP para nivel $levelName';
  }

  @override
  String get oppMaxLevel => '¡Nivel máximo!';

  @override
  String get oppBoostEarned => '¡Impulso de perfil obtenido!';

  @override
  String oppBoostProgress(int count) {
    return '$count/3 oportunidades para impulso';
  }

  @override
  String oppProfileBoosted(String timeLabel) {
    return '¡Perfil impulsado! Quedan $timeLabel';
  }

  @override
  String oppError(String error) {
    return 'Error: $error';
  }

  @override
  String get oppTimeJustNow => 'Ahora mismo';

  @override
  String oppTimeMinAgo(int minutes) {
    return 'hace $minutes min';
  }

  @override
  String oppTimeHourAgo(int hours) {
    return 'hace $hours horas';
  }

  @override
  String oppTimeDayAgo(int days) {
    return 'hace $days días';
  }

  @override
  String oppTimeHours(int hours) {
    return '$hours horas';
  }

  @override
  String oppTimeMinutes(int minutes) {
    return '$minutes minutos';
  }

  @override
  String get oppUnderReviewTitle => 'Tu perfil está en revisión';

  @override
  String get oppUnderReviewSubtitle => 'El equipo de AnySkill está revisando tu perfil';

  @override
  String get oppUnderReviewBody => 'Te notificaremos cuando la verificación esté completa';

  @override
  String get oppUnderReviewContact => 'Contactar Soporte';

  @override
  String get oppUnderReviewStep1 => 'Perfil enviado';

  @override
  String get oppUnderReviewStep2 => 'En revisión';

  @override
  String get oppUnderReviewStep3 => 'Aprobación final';

  @override
  String get requestsEmpty => 'Sin solicitudes';

  @override
  String get requestsEmptySubtitle => 'Aún no se han publicado solicitudes';

  @override
  String get requestsChatNow => 'Enviar Mensaje';

  @override
  String get requestsClosed => 'Cerrada';

  @override
  String get requestsConfirmPay => 'Confirmar y Pagar';

  @override
  String get requestsDefaultExpert => 'Profesional';

  @override
  String get requestsEscrowTooltip => 'Los fondos se mantienen en depósito hasta completar el trabajo';

  @override
  String get requestsMatchLabel => 'Coincidencia';

  @override
  String get requestsTopMatch => 'Mejor Coincidencia';

  @override
  String get requestsVerifiedBadge => 'Verificado';

  @override
  String get requestsMoneyProtected => 'Tu dinero está protegido';

  @override
  String get requestsWaiting => 'Esperando';

  @override
  String get requestsWaitingProviders => 'Esperando proveedores...';

  @override
  String get requestsJustNow => 'Ahora mismo';

  @override
  String requestsMinutesAgo(int minutes) {
    return 'hace $minutes min';
  }

  @override
  String requestsHoursAgo(int hours) {
    return 'hace $hours horas';
  }

  @override
  String requestsDaysAgo(int days) {
    return 'hace $days días';
  }

  @override
  String requestsInterested(int count) {
    return '$count interesados';
  }

  @override
  String requestsViewInterested(int count) {
    return 'Ver $count interesados';
  }

  @override
  String requestsOrderCount(int count) {
    return '$count pedidos';
  }

  @override
  String requestsHiredAgo(String label) {
    return 'Contratado $label';
  }

  @override
  String requestsPricePerHour(String price) {
    return '₪$price/hora';
  }

  @override
  String get timeNow => 'Ahora';

  @override
  String get timeOneHour => 'Hora';

  @override
  String timeMinutesAgo(int minutes) {
    return 'hace $minutes min';
  }

  @override
  String timeHoursAgo(int hours) {
    return 'hace $hours horas';
  }

  @override
  String get urgentBannerRequests => 'Solicitudes Urgentes';

  @override
  String get urgentBannerPending => 'Pendientes';

  @override
  String get urgentBannerServiceNeeded => 'Se Necesita Servicio';

  @override
  String get urgentBannerCustomerWaiting => 'Cliente Esperando';

  @override
  String get calendarTitle => 'Calendario';

  @override
  String get calendarRefresh => 'Actualizar';

  @override
  String get calendarNoEvents => 'Sin eventos';

  @override
  String get calendarStatusCompleted => 'Completado';

  @override
  String get calendarStatusPending => 'Pendiente';

  @override
  String get calendarStatusWaiting => 'En Espera';

  @override
  String get creditsLabel => 'Créditos';

  @override
  String creditsDiscountAvailable(int discount) {
    return '¡Descuento del $discount% disponible!';
  }

  @override
  String creditsToNextDiscount(int remaining) {
    return '$remaining créditos para el próximo descuento';
  }

  @override
  String get serviceFullSession => 'Sesión Completa';

  @override
  String get serviceSingleLesson => 'Clase Individual';

  @override
  String get serviceExtendedLesson => 'Clase Extendida';

  @override
  String get validationNameRequired => 'El nombre es obligatorio';

  @override
  String get validationNameLength => 'El nombre debe tener al menos 2 caracteres';

  @override
  String get validationNameTooLong => 'El nombre es demasiado largo';

  @override
  String get validationNameForbidden => 'El nombre contiene caracteres prohibidos';

  @override
  String get validationCategoryRequired => 'Por favor selecciona una categoría';

  @override
  String get validationRoleRequired => 'Por favor selecciona un tipo de usuario';

  @override
  String get validationPriceInvalid => 'Precio no válido';

  @override
  String get validationPricePositive => 'El precio debe ser positivo';

  @override
  String get validationAboutTooLong => 'La descripción es demasiado larga';

  @override
  String get validationAboutForbidden => 'La descripción contiene caracteres prohibidos';

  @override
  String get validationFieldForbidden => 'El campo contiene caracteres prohibidos';

  @override
  String get validationUrlHttps => 'La URL debe comenzar con https://';

  @override
  String get vipSheetHeader => 'AnySkill VIP';

  @override
  String get vipPriceMonthly => '₪99/mes';

  @override
  String get vipActivateButton => 'Activar VIP';

  @override
  String get vipActivationSuccess => '¡VIP activado exitosamente!';

  @override
  String get vipInsufficientBalance => 'Saldo insuficiente para activar VIP';

  @override
  String get vipInsufficientTooltip => 'Recarga tu cartera para activar VIP';

  @override
  String get vipBenefit1 => 'Prioridad en resultados de búsqueda';

  @override
  String get vipBenefit2 => 'Insignia VIP en el perfil';

  @override
  String get vipBenefit3 => 'Prioridad en oportunidades';

  @override
  String get vipBenefit4 => 'Soporte premium';

  @override
  String withdrawMinBalance(int amount) {
    return 'El monto mínimo de retiro es $amount ₪';
  }

  @override
  String get withdrawAvailableBalance => 'Saldo disponible para retiro';

  @override
  String get withdrawBankSection => 'Datos Bancarios';

  @override
  String get withdrawBankName => 'Nombre del Banco';

  @override
  String get withdrawBankBranch => 'Sucursal';

  @override
  String get withdrawBankAccount => 'Número de Cuenta';

  @override
  String get withdrawBankRequired => 'El nombre del banco es obligatorio';

  @override
  String get withdrawBranchRequired => 'La sucursal es obligatoria';

  @override
  String get withdrawAccountMinDigits => 'El número de cuenta debe tener al menos 5 dígitos';

  @override
  String get withdrawBankEncryptedNotice => 'Los datos están encriptados y seguros';

  @override
  String get withdrawEncryptedNotice => 'La información está encriptada y segura';

  @override
  String get withdrawBankTransferPending => 'Transferencia bancaria en proceso';

  @override
  String get withdrawCertSection => 'Certificados';

  @override
  String get withdrawCertHint => 'Sube licencia comercial / certificado de exención';

  @override
  String get withdrawCertUploadBtn => 'Subir Certificado';

  @override
  String get withdrawCertReplace => 'Reemplazar Certificado';

  @override
  String get withdrawDeclarationSection => 'Declaración';

  @override
  String get withdrawDeclarationText => 'Declaro responsabilidad exclusiva por declarar mis impuestos conforme a la ley';

  @override
  String get withdrawDeclarationSuffix => '(Sección 6 de los Términos)';

  @override
  String get withdrawTaxStatusTitle => 'Tipo de Negocio';

  @override
  String get withdrawTaxStatusSubtitle => 'Selecciona tu tipo de negocio';

  @override
  String get withdrawTaxIndividual => 'Comerciante Exento';

  @override
  String get withdrawTaxIndividualSub => 'Exento de cobro de IVA';

  @override
  String get withdrawTaxIndividualBadge => 'Exento';

  @override
  String get withdrawTaxBusiness => 'Comerciante Autorizado';

  @override
  String get withdrawTaxBusinessSub => 'Obligado a cobrar IVA';

  @override
  String get withdrawIndividualTitle => 'Datos de Comerciante Exento';

  @override
  String get withdrawIndividualDesc => 'Ingresa los datos de comerciante exento';

  @override
  String get withdrawIndividualFormTitle => 'Formulario Comerciante Exento';

  @override
  String get withdrawBusinessFormTitle => 'Formulario Comerciante Autorizado';

  @override
  String get withdrawNoCertError => 'Por favor sube un certificado comercial';

  @override
  String get withdrawNoDeclarationError => 'Por favor confirma la declaración';

  @override
  String get withdrawSelectBankError => 'Por favor selecciona un banco';

  @override
  String withdrawSubmitButton(String amount) {
    return 'Retirar $amount';
  }

  @override
  String get withdrawSubmitError => 'Error al enviar la solicitud';

  @override
  String get withdrawSuccessTitle => '¡Solicitud Enviada!';

  @override
  String withdrawSuccessSubtitle(String amount) {
    return 'Solicitud de retiro por $amount enviada exitosamente';
  }

  @override
  String get withdrawSuccessNotice => 'La transferencia bancaria se procesará en 3-5 días hábiles';

  @override
  String get withdrawTimeline1Title => 'Solicitud Enviada';

  @override
  String get withdrawTimeline1Sub => 'Solicitud recibida por el sistema';

  @override
  String get withdrawTimeline2Title => 'En Proceso';

  @override
  String get withdrawTimeline2Sub => 'El equipo está procesando tu solicitud';

  @override
  String get withdrawTimeline3Title => 'Completado';

  @override
  String get withdrawTimeline3Sub => 'Fondos transferidos a tu cuenta';

  @override
  String get pendingCatsApproved => 'Categoría aprobada';

  @override
  String get pendingCatsRejected => 'Categoría rechazada';

  @override
  String get helpCenterTitle => 'Centro de Ayuda';

  @override
  String get helpCenterTooltip => 'Ayuda';

  @override
  String get helpCenterCustomerWelcome => 'Bienvenido al Centro de Ayuda';

  @override
  String get helpCenterCustomerFaq => 'Preguntas Frecuentes para Clientes';

  @override
  String get helpCenterCustomerSupport => 'Soporte al Cliente';

  @override
  String get helpCenterProviderWelcome => 'Bienvenido al Centro de Ayuda para Proveedores';

  @override
  String get helpCenterProviderFaq => 'Preguntas Frecuentes para Proveedores';

  @override
  String get helpCenterProviderSupport => 'Soporte al Proveedor';

  @override
  String get languageTitle => 'Idioma';

  @override
  String get languageSectionLabel => 'Seleccionar Idioma';

  @override
  String get languageHe => 'עברית';

  @override
  String get languageEn => 'English';

  @override
  String get languageEs => 'Español';

  @override
  String get languageAr => 'العربية';

  @override
  String get systemWalletEnterNumber => 'Ingresa un número válido';

  @override
  String get updateBannerText => 'Nueva versión disponible';

  @override
  String get updateNowButton => 'Actualizar Ahora';

  @override
  String get xpLevelBronze => 'Novato';

  @override
  String get xpLevelSilver => 'Profesional';

  @override
  String get xpLevelGold => 'Oro';

  @override
  String get bizAiTitle => 'Inteligencia de Negocios';

  @override
  String get bizAiSubtitle => 'Análisis y pronóstico con IA';

  @override
  String get bizAiLoading => 'Cargando datos...';

  @override
  String get bizAiRefreshData => 'Actualizar Datos';

  @override
  String get bizAiNoData => 'No hay datos disponibles';

  @override
  String bizAiError(String error) {
    return 'Error: $error';
  }

  @override
  String get bizAiSectionFinancial => 'Finanzas';

  @override
  String get bizAiSectionMarket => 'Mercado';

  @override
  String get bizAiSectionAlerts => 'Alertas';

  @override
  String get bizAiSectionAiOps => 'Operaciones IA';

  @override
  String get bizAiDailyCommission => 'Comisión Diaria';

  @override
  String get bizAiWeeklyProjection => 'Proyección Semanal';

  @override
  String get bizAiWeeklyForecast => 'Pronóstico Semanal';

  @override
  String get bizAiExpectedRevenue => 'Ingresos Esperados';

  @override
  String get bizAiForecastBadge => 'Pronóstico';

  @override
  String get bizAiActualToDate => 'Real a la Fecha';

  @override
  String get bizAiAccuracy => 'Precisión';

  @override
  String get bizAiModelAccuracy => 'Precisión del Modelo';

  @override
  String get bizAiModelAccuracyDetail => 'Precisión de predicción de ingresos';

  @override
  String get bizAiNoChartData => 'Sin datos para gráfico';

  @override
  String get bizAiNoOrderData => 'Sin datos de pedidos';

  @override
  String get bizAiSevenDays => '7 Días';

  @override
  String get bizAiLast7Days => 'Últimos 7 Días';

  @override
  String get bizAiExecSummary => 'Resumen Ejecutivo';

  @override
  String get bizAiActivityToday => 'Actividad de Hoy';

  @override
  String get bizAiApprovalQueue => 'Cola de Aprobación';

  @override
  String bizAiPending(int count) {
    return '$count pendientes';
  }

  @override
  String get bizAiPendingLabel => 'Pendientes';

  @override
  String get bizAiApproved => 'Aprobado';

  @override
  String get bizAiRejected => 'Rechazado';

  @override
  String get bizAiApprovedTotal => 'Total Aprobados';

  @override
  String get bizAiTapToReview => 'Toca para revisar';

  @override
  String get bizAiCategoriesApproved => 'Categorías Aprobadas';

  @override
  String get bizAiNewCategories => 'Nuevas Categorías';

  @override
  String get bizAiMarketOpportunities => 'Oportunidades de Mercado';

  @override
  String get bizAiMarketOppsCard => 'Oportunidades de Mercado';

  @override
  String get bizAiHighValueCategories => 'Categorías de Alto Valor';

  @override
  String get bizAiHighValueHint => 'Categorías con alto potencial de ingresos';

  @override
  String bizAiProviders(int count) {
    return '$count proveedores';
  }

  @override
  String get bizAiPopularSearches => 'Búsquedas Populares';

  @override
  String get bizAiNoSearchData => 'Sin datos de búsqueda';

  @override
  String get bizAiNichesNoProviders => 'Nichos Sin Proveedores';

  @override
  String get bizAiNoOpportunities => 'Sin oportunidades en este momento';

  @override
  String bizAiRecruitForQuery(String query) {
    return 'Reclutar proveedores para \"$query\"';
  }

  @override
  String get bizAiZeroResultsHint => 'Búsquedas sin resultados — oportunidad de reclutamiento';

  @override
  String bizAiSearches(int count) {
    return 'Búsquedas: $count+';
  }

  @override
  String bizAiSearchCount(int count) {
    return '$count búsquedas';
  }

  @override
  String get bizAiAlertHistory => 'Historial de Alertas';

  @override
  String get bizAiAlertThreshold => 'Umbral de Alerta';

  @override
  String get bizAiAlertThresholdHint => 'Búsquedas mínimas para alerta';

  @override
  String get bizAiSaveThreshold => 'Guardar Umbral';

  @override
  String get bizAiReset => 'Restablecer';

  @override
  String get bizAiNoAlerts => 'Sin alertas';

  @override
  String bizAiAlertCount(int count) {
    return '$count alertas';
  }

  @override
  String bizAiMinutesAgo(int minutes) {
    return 'hace $minutes min';
  }

  @override
  String bizAiHoursAgo(int hours) {
    return 'hace $hours horas';
  }

  @override
  String bizAiDaysAgo(int days) {
    return 'hace $days días';
  }

  @override
  String get tabProfile => 'Perfil';

  @override
  String get searchPlaceholder => 'Buscar profesional, servicio...';

  @override
  String get searchTitle => 'Buscar';

  @override
  String get discoverCategories => 'Descubrir categorías';

  @override
  String get confirm => 'Confirmar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get submit => 'Enviar';

  @override
  String get next => 'Siguiente';

  @override
  String get back => 'Atrás';

  @override
  String get delete => 'Eliminar';

  @override
  String get currencySymbol => '₪';

  @override
  String get statusPaidEscrow => 'Pendiente';

  @override
  String get statusExpertCompleted => 'Completado — Pendiente de aprobación';

  @override
  String get statusCompleted => 'Completado';

  @override
  String get statusCancelled => 'Cancelado';

  @override
  String get statusDispute => 'En disputa';

  @override
  String get statusPendingPayment => 'Pago pendiente';

  @override
  String get profileCustomer => 'Cliente';

  @override
  String get profileProvider => 'Proveedor';

  @override
  String get profileOrders => 'Pedidos';

  @override
  String get profileRating => 'Calificación';

  @override
  String get profileReviews => 'Reseñas';

  @override
  String get reviewsPlaceholder => 'Cuéntanos tu experiencia...';

  @override
  String get reviewSubmit => 'Enviar reseña';

  @override
  String get ratingLabel => 'Califica el servicio';

  @override
  String get walletBalance => 'Saldo';

  @override
  String get openChat => 'Abrir chat';

  @override
  String get quickRequest => 'Solicitud rápida';

  @override
  String get trendingBadge => 'Tendencia';

  @override
  String get isCurrentRtl => 'false';

  @override
  String get taxDeclarationText => 'Declaro responsabilidad exclusiva de reporte fiscal.';

  @override
  String get loginTitle => 'Iniciar sesión';

  @override
  String get loginSubtitle => 'Inicia sesión en tu cuenta';

  @override
  String get errorGenericLogin => 'Error al iniciar sesión';

  @override
  String get subCategoryPrompt => 'Elige subcategoría';

  @override
  String get emptyActivityTitle => 'Sin actividad';

  @override
  String get emptyActivityCta => 'Comenzar';

  @override
  String get errorNetworkTitle => 'Error de red';

  @override
  String get errorNetworkBody => 'Revisa tu conexión';

  @override
  String get errorProfileLoad => 'Error al cargar perfil';

  @override
  String get forgotPassword => '¿Olvidaste tu contraseña?';

  @override
  String get signupButton => 'Registrarse';

  @override
  String get tosAgree => 'Acepto los Términos de Servicio';

  @override
  String get tosTitle => 'Términos de Servicio';

  @override
  String get tosVersion => 'Versión 1.0';

  @override
  String get urgentCustomerLabel => 'Servicio urgente';

  @override
  String get urgentProviderLabel => 'Oportunidades urgentes';

  @override
  String get urgentOpenButton => 'Abrir';

  @override
  String get walletMinWithdraw => 'Mínimo para retirar';

  @override
  String get withdrawalPending => 'Retiro pendiente';

  @override
  String get withdrawFunds => 'Retirar fondos';

  @override
  String onboardingError(String error) {
    return 'Error: $error';
  }

  @override
  String onboardingUploadError(String error) {
    return 'Error de subida: $error';
  }

  @override
  String get onboardingWelcome => '¡Bienvenido!';

  @override
  String get availabilityUpdated => 'Disponibilidad actualizada';

  @override
  String get bizAiRecruitNow => 'Reclutar Ahora';

  @override
  String get chatEmptyState => 'No hay mensajes aún';

  @override
  String get chatLastMessageDefault => 'Sin último mensaje';

  @override
  String get chatSearchHint => 'Buscar en chats...';

  @override
  String get chatUserDefault => 'Usuario';

  @override
  String get deleteChatConfirm => 'Confirmar';

  @override
  String get deleteChatContent => '¿Estás seguro de que deseas eliminar este chat?';

  @override
  String get deleteChatSuccess => 'Chat eliminado exitosamente';

  @override
  String get deleteChatTitle => 'Eliminar Chat';

  @override
  String get disputeActionsSection => 'Acciones';

  @override
  String get disputeAdminNote => 'Nota del Administrador';

  @override
  String get disputeAdminNoteHint => 'Agregar nota (opcional)';

  @override
  String get disputeArbitrationCenter => 'Centro de Arbitraje';

  @override
  String get disputeChatHistory => 'Historial de Chat';

  @override
  String get disputeDescription => 'Descripción';

  @override
  String get disputeEmptySubtitle => 'No hay disputas abiertas en este momento';

  @override
  String get disputeEmptyTitle => 'Sin Disputas';

  @override
  String get disputeHint => 'Describe el problema en detalle';

  @override
  String get disputeIdPrefix => 'Disputa #';

  @override
  String get disputeIrreversible => 'Esta acción no se puede deshacer';

  @override
  String get disputeLockedEscrow => 'Bloqueado en Escrow';

  @override
  String get disputeLockedSuffix => '₪';

  @override
  String get disputeNoChatId => 'Sin ID de chat';

  @override
  String get disputeNoMessages => 'Sin mensajes';

  @override
  String get disputeNoReason => 'Sin razón proporcionada';

  @override
  String get disputeOpenDisputes => 'Disputas Abiertas';

  @override
  String get disputePartiesSection => 'Partes';

  @override
  String get disputePartyProvider => 'el proveedor';

  @override
  String get disputeReasonSection => 'Razón de la Disputa';

  @override
  String get disputeRefundLabel => 'Reembolso';

  @override
  String get disputeReleaseLabel => 'Liberar Pago';

  @override
  String get disputeResolving => 'Procesando...';

  @override
  String get disputeSplitLabel => 'División';

  @override
  String get disputeSystemSender => 'Sistema';

  @override
  String get disputeTapForDetails => 'Toca para ver detalles';

  @override
  String get disputeTitle => 'Disputa';

  @override
  String get editProfileTitle => 'Editar Perfil';

  @override
  String get helpCenterInputHint => 'Escribe tu pregunta aquí...';

  @override
  String get logoutButton => 'Cerrar Sesión';

  @override
  String get markAllReadSuccess => 'Todas las notificaciones marcadas como leídas';

  @override
  String get markedDoneSuccess => 'Marcado como hecho exitosamente';

  @override
  String get noCategoriesYet => 'Sin categorías aún';

  @override
  String get notifClearAll => 'Limpiar Todo';

  @override
  String get notifEmptySubtitle => 'No tienes notificaciones nuevas';

  @override
  String get notifEmptyTitle => 'Sin Notificaciones';

  @override
  String get notifOpen => 'Abrir';

  @override
  String get notificationsTitle => 'Notificaciones';

  @override
  String get oppNotifTitle => 'Nuevo Interés';

  @override
  String get pendingCatsApprove => 'Aprobar';

  @override
  String get pendingCatsEmptySubtitle => 'No hay solicitudes de categoría pendientes';

  @override
  String get pendingCatsEmptyTitle => 'Sin Solicitudes';

  @override
  String get pendingCatsImagePrompt => 'Subir imagen de categoría';

  @override
  String get pendingCatsProviderDesc => 'Descripción del proveedor';

  @override
  String get pendingCatsReject => 'Rechazar';

  @override
  String get pendingCatsSectionPending => 'Pendientes';

  @override
  String get pendingCatsSectionReviewed => 'Revisadas';

  @override
  String get pendingCatsStatusApproved => 'Aprobado';

  @override
  String get pendingCatsStatusRejected => 'Rechazado';

  @override
  String get pendingCatsTitle => 'Solicitudes de Categoría';

  @override
  String get pendingCatsAiReason => 'Razón de IA';

  @override
  String get profileLoadError => 'Error al cargar perfil';

  @override
  String get requestsBestValue => 'Mejor Valor';

  @override
  String get requestsFastResponse => 'Respuesta Rápida';

  @override
  String get requestsInterestedTitle => 'Interesados';

  @override
  String get requestsNoInterested => 'Nadie interesado aún';

  @override
  String get requestsTitle => 'Solicitudes';

  @override
  String get submitDispute => 'Enviar Disputa';

  @override
  String get systemWalletFeePanel => 'Comisión de Plataforma';

  @override
  String get systemWalletInvalidNumber => 'Número no válido';

  @override
  String get systemWalletUpdateFee => 'Actualizar Comisión';

  @override
  String get tosAcceptButton => 'Acepto';

  @override
  String get tosBindingNotice => 'Al confirmar, aceptas los Términos de Servicio';

  @override
  String get tosFullTitle => 'Términos de Servicio Completos';

  @override
  String get tosLastUpdated => 'Última Actualización';

  @override
  String get withdrawExistingCert => 'Certificado existente';

  @override
  String get withdrawUploadError => 'Error al subir archivo';

  @override
  String get xpAddAction => 'Agregar';

  @override
  String get xpAddEventButton => 'Agregar Evento';

  @override
  String get xpAddEventTitle => 'Agregar Evento XP';

  @override
  String get xpDeleteEventTitle => 'Eliminar Evento';

  @override
  String get xpEditEventTitle => 'Editar Evento XP';

  @override
  String get xpEventAdded => 'Evento agregado exitosamente';

  @override
  String get xpEventDeleted => 'Evento eliminado exitosamente';

  @override
  String get xpEventUpdated => 'Evento actualizado exitosamente';

  @override
  String get xpEventsEmpty => 'Sin eventos XP';

  @override
  String get xpEventsSection => 'Eventos XP';

  @override
  String get xpFieldDesc => 'Descripción';

  @override
  String get xpFieldId => 'ID';

  @override
  String get xpFieldIdHint => 'Ingresa un ID único';

  @override
  String get xpFieldName => 'Nombre';

  @override
  String get xpFieldPoints => 'Puntos';

  @override
  String get xpLevelsError => 'Error al guardar niveles';

  @override
  String get xpLevelsSaved => 'Niveles guardados exitosamente';

  @override
  String get xpLevelsSubtitle => 'Establece los umbrales de XP para cada nivel';

  @override
  String get xpLevelsTitle => 'Niveles XP';

  @override
  String get xpManagerSubtitle => 'Administrar eventos y niveles de XP';

  @override
  String get xpManagerTitle => 'Administrador XP';

  @override
  String get xpReservedId => 'ID reservado';

  @override
  String get xpSaveAction => 'Guardar';

  @override
  String get xpSaveLevels => 'Guardar Niveles';

  @override
  String get xpTooltipDelete => 'Eliminar';

  @override
  String get xpTooltipEdit => 'Editar';

  @override
  String bizAiThresholdUpdated(int value) {
    return 'Umbral actualizado a $value';
  }

  @override
  String disputeErrorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String disputeExistingNote(String note) {
    return 'Nota del administrador: $note';
  }

  @override
  String disputeOpenedAt(String date) {
    return 'Abierto el $date';
  }

  @override
  String disputeRefundSublabel(String amount) {
    return 'Reembolso completo — $amount ₪ al cliente';
  }

  @override
  String disputeReleaseSublabel(String amount) {
    return 'Liberar — $amount ₪ al proveedor';
  }

  @override
  String disputeSplitSublabel(String amount) {
    return 'División — $amount ₪ a cada parte';
  }

  @override
  String editCategorySaveError(String error) {
    return 'Error al guardar: $error';
  }

  @override
  String oppInterestChatMessage(String providerName, String description) {
    return 'Hola, soy $providerName y me encantaría ayudar: $description';
  }

  @override
  String oppNotifBody(String providerName) {
    return '$providerName está interesado en tu oportunidad';
  }

  @override
  String pendingCatsErrorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String pendingCatsSubCategory(String name) {
    return 'Sub-categoría: $name';
  }

  @override
  String xpDeleteEventConfirm(String name) {
    return '¿Eliminar $name?';
  }

  @override
  String xpErrorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String xpEventsCount(int count) {
    return '$count eventos';
  }
}
