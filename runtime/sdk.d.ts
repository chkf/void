export type Result<T> =
  | { success: true; data: T }
  | { success: false; error: { code: string; message: string } };

export interface RequestOptions { signal?: AbortSignal; timeoutMs?: number }
type Call<P, T> = (params: P, options?: RequestOptions) => Promise<Result<T>>;
type OptionalCall<P, T> = (params?: P, options?: RequestOptions) => Promise<Result<T>>;
type NoArgs<T> = OptionalCall<Record<string, never>, T>;
export type NativeEvent = { id: string; type: string; data: unknown };
export type Authorization = "authorized" | "denied" | "restricted" | "notDetermined" | "limited" | "unknown";
export type FileEncoding = "utf8" | "base64";
type Path = { path: string };
type To = { to: string };
type Id = { id: string };
type FileWrite = Path & { data: string; encoding?: FileEncoding };
export type FileEntry = { name: string; type: "file" | "directory" | "link"; size: number; modified: number };
export type FilePickerOptions = { multiple?: boolean; directory?: string; types?: string[] };
export type MediaItem = Path & { type: "image" | "video"; contentType: string; assetId?: string };
export type PhotoAuthorization = "authorized" | "limited" | "notDetermined" | "restricted" | "denied";
export type MediaInfo = { duration: number; width?: number; height?: number; frameRate?: number };
export type AudioRoute = { inputs: { name: string; type: string }[]; outputs: { name: string; type: string }[] };
export type Position = { latitude: number; longitude: number; accuracy: number; altitude: number; speed: number; timestamp: string };
export type Accuracy = { accuracy?: "best" | "nearestTenMeters" | "hundredMeters" | "kilometer" };
export type Place = { name: string; city: string; street: string; country: string; latitude?: number; longitude?: number };
export type DateRange = { startDate: string; endDate: string };
export type CalendarList = Id & { title: string; writable: boolean };
export type EventFields = DateRange & { title: string; allDay?: boolean; calendarId?: string; notes?: string; location?: string };
export type ReminderFields = { title: string; listId?: string; notes?: string; completed?: boolean; dueDate?: string | null };
export type ContactFields = { givenName?: string; familyName?: string; organization?: string; phones?: string[]; emails?: string[] };
export type NotificationCategory = Id & { actions?: { id: string; title: string }[] };
export type PendingNotification = Id & { title:string; body:string; repeats:boolean; nextDate?:string };
export type Peripheral = { peripheral: string };
export type Service = Peripheral & { service: string };
export type Characteristic = Service & { characteristic: string };
export type CharacteristicInfo = Id & { read: boolean; write: boolean; writeWithoutResponse: boolean; notify: boolean };
export type NDEFRecord = { format:number; type:string; identifier?:string; payload:string; text?:string; url?:string };
export type HealthType = "steps" | "heartRate" | "sleep" | "activeEnergy" | "exerciseMinutes" | "workouts" | "activitySummary";
export type HealthValue = { type?: HealthType; id?:string; startDate?:string; endDate?:string; date?:string; value?:number; unit?:string;
  activity?:number; duration?:number; meters?:number; kilocalories?:number; exerciseMinutes?:number; standHours?:number };
export type Home = { home: string };
export type HomeCharacteristic = Home & { characteristic: string };
export type HomeValue = string | number | boolean | { base64: string } | null;
export type HomeAccessory = Id & { name:string; reachable:boolean; services: (Id & { name:string; characteristics:(Id & { name:string; type:string; properties:string[] })[] })[] };
export type NetworkStatus = { connected:boolean; expensive:boolean; constrained:boolean; interface:"wifi"|"cellular"|"other" };
export type HTTPRequest = { url:string; method?:"GET"|"POST"|"PUT"|"PATCH"|"DELETE"|"HEAD"; headers?:Record<string,string>; timeout?:number; progressId?:string; body?:string; base64?:string };
export type HTTPInfo = { status:number; headers: Record<string,string>; url:string };
export type HTTPResult = HTTPInfo & { base64:string; text?:string };
export type SQLValue = string | number | boolean | null | { base64: string };
export type SQLStatement = { sql: string; params?: SQLValue[] };
export type SQLChange = { changes: number; lastInsertId: number };
export type GraphicsCapabilities = { canvas2D:boolean; webgl:boolean; webgl2:boolean; wasm:boolean; animation:boolean; imageFormats:string[]; sqlite:string; maxChunkBytes:number };

export interface NativeSDK {
  readonly version: string;
  onEvent(listener: (event: NativeEvent) => void): () => void;
  stop(id: string): Promise<Result<null>>;
  fs: {
    readFile: Call<Path & { encoding?: FileEncoding }, string>;
    writeFile: Call<FileWrite, null>;
    appendFile: Call<FileWrite, null>;
    readChunk: Call<Path & { offset?:number; length?:number; encoding?:FileEncoding }, string>;
    writeChunk: Call<FileWrite & { offset:number }, null>;
    deleteFile: Call<Path, null>;
    copyFile: Call<Path & To, null>;
    moveFile: Call<Path & To, null>;
    mkdir: Call<Path, null>;
    readdir: Call<Path, FileEntry[]>;
    stat: Call<Path, FileEntry>;
    exists: Call<Path, boolean>;
    watch: Call<Path, string>;
    pick: OptionalCall<FilePickerOptions, string[]>;
    importFile: OptionalCall<FilePickerOptions, string[]>;
    exportFile: Call<Path, null>;
    share: Call<Path, boolean>;
  };
  photos: {
    authorization: NoArgs<{ readWrite: PhotoAuthorization; addOnly: PhotoAuthorization }>;
    pick: OptionalCall<{ mediaTypes?: ("image"|"video")[]; multiple?:boolean }, MediaItem[]>;
    requestAccess: NoArgs<PhotoAuthorization>;
    asset: Call<Id & { to?:string }, { id:string; type:"image"|"video"; width:number; height:number; duration:number; filename:string; created?:string; path?:string }>;
    thumbnail: Call<Id & { size?:number; to?:string }, string>;
    save: Call<Path & { type:"image"|"video" }, string | null>;
  };
  camera: {
    authorization: NoArgs<Authorization>;
    available: NoArgs<{ front:boolean; back:boolean }>;
    open: OptionalCall<{ position?:"front"|"back"; microphone?:boolean }, { position:string; flash:boolean; video:boolean }>;
    switchCamera: OptionalCall<{ position?:"front"|"back" }, string>;
    configure: Call<{ flash?:"off"|"on"|"auto"; focus?:{ x:number; y:number }; exposure?:number }, null>;
    capturePhoto: OptionalCall<{ to?:string }, string>;
    startRecording: OptionalCall<{ to?:string }, string>;
    stopRecording: NoArgs<string>;
    close: NoArgs<null>;
  };
  audio: {
    authorization: NoArgs<Authorization>;
    record: OptionalCall<{ to?:string; sampleRate?:number; channels?:1|2 }, string>;
    stopRecording: NoArgs<string>;
    play: Call<Path, { duration:number }>;
    pause: OptionalCall<{ target?:"playback"|"recording" }, null>;
    resume: OptionalCall<{ target?:"playback"|"recording" }, null>;
    stop: NoArgs<null>;
    volume: OptionalCall<{ value?:number }, number>;
    info: Call<Path, { sampleRate:number; channels:number; frames:number; duration:number }>;
    session: OptionalCall<{ category?:"playback"|"ambient"|"playAndRecord" }, AudioRoute>;
    route: NoArgs<AudioRoute>;
    watchRoute: NoArgs<string>;
    importFile: OptionalCall<FilePickerOptions, string[]>;
    exportFile: Call<Path, null>;
  };
  video: {
    play: Call<Path, string>;
    pause: NoArgs<null>;
    resume: NoArgs<null>;
    seek: Call<{ seconds:number }, boolean>;
    stop: NoArgs<null>;
    info: Call<Path, MediaInfo>;
    thumbnail: Call<Path & { seconds?:number; size?:number; to?:string }, string>;
    transcode: Call<Path & To & { quality?:"low"|"medium"|"high"|"passthrough" }, string>;
    importFile: OptionalCall<FilePickerOptions, string[]>;
    exportFile: Call<Path, null>;
  };
  location: {
    authorization: NoArgs<{ status:"always"|"whenInUse"|"denied"|"restricted"|"notDetermined"; accuracy:"full"|"reduced" }>;
    current: OptionalCall<Accuracy, Position>;
    watch: OptionalCall<Accuracy, string>;
    heading: OptionalCall<Accuracy, string>;
    geocode: Call<{ address:string }, Place[]>;
    reverseGeocode: Call<{ latitude:number; longitude:number }, Place[]>;
  };
  calendar: {
    authorization: NoArgs<"writeOnly"|"fullAccess"|"denied"|"notDetermined"|"restricted"|"unknown">;
    listCalendars: NoArgs<CalendarList[]>;
    events: Call<DateRange & { calendarIds?:string[]; limit?:number }, (Id & EventFields)[]>;
    createEvent: Call<EventFields, string>;
    updateEvent: Call<Id & Partial<EventFields>, string>;
    deleteEvent: Call<Id, null>;
  };
  reminders: {
    authorization: NoArgs<"fullAccess"|"denied"|"notDetermined"|"restricted"|"unknown">;
    lists: NoArgs<CalendarList[]>;
    list: OptionalCall<{ listIds?:string[]; limit?:number }, (Id & ReminderFields)[]>;
    create: Call<ReminderFields, string>;
    update: Call<Id & Partial<ReminderFields>, string>;
    remove: Call<Id, null>;
    createList: Call<{ title:string }, CalendarList>;
    updateList: Call<Id & { title:string }, CalendarList>;
    deleteList: Call<Id, null>;
  };
  contacts: {
    authorization: NoArgs<Authorization>;
    search: OptionalCall<{ name?:string; limit?:number }, (Id & ContactFields)[]>;
    get: Call<Id, Id & ContactFields>;
    create: Call<ContactFields, string>;
    update: Call<Id & ContactFields, string>;
    remove: Call<Id, null>;
  };
  notifications: {
    authorization: NoArgs<"notDetermined"|"denied"|"authorized"|"provisional"|"ephemeral"|"unknown">;
    request: NoArgs<boolean>;
    schedule: Call<{ title:string; body?:string; id?:string; afterSeconds?:number; at?:string; repeats?:boolean; category?:string; sound?:boolean }, string>;
    cancel: Call<Id, null>;
    pending: NoArgs<PendingNotification[]>;
    categories: NoArgs<string[]>;
    setCategories: Call<{ categories:NotificationCategory[] }, null>;
    responses: OptionalCall<{ consume?:boolean }, (Id & { action:string; date:string })[]>;
  };
  bluetooth: {
    authorization: NoArgs<Authorization>;
    state: NoArgs<"on"|"off"|"unsupported"|"denied"|"resetting"|"unknown">;
    scan: OptionalCall<{ services?:string[] }, string>;
    connect: Call<Peripheral, string>;
    disconnect: Call<Peripheral, null>;
    services: Call<Peripheral, string[]>;
    characteristics: Call<Service, CharacteristicInfo[]>;
    read: Call<Characteristic, string>;
    write: Call<Characteristic & { data:string; withResponse?:boolean }, null>;
    subscribe: Call<Characteristic, string>;
  };
  nfc: {
    available: NoArgs<boolean>;
    read: OptionalCall<{ message?:string }, { records:NDEFRecord[]; capacity?:number; writable?:boolean }>;
    write: Call<{ records:({ text:string }|{ url:string }|NDEFRecord)[]; message?:string }, { bytes:number; capacity:number }>;
  };
  health: {
    available: NoArgs<boolean>;
    types: NoArgs<HealthType[]>;
    authorization: Call<{ type:HealthType }, { read:"notDisclosed"; write:"authorized"|"denied"|"notDetermined" }>;
    authorizeRead: Call<{ types:HealthType[] }, null>;
    authorizeWrite: Call<{ types:HealthType[] }, null>;
    query: Call<DateRange & { type:HealthType; limit?:number }, HealthValue[]>;
    write: Call<DateRange & { type:HealthType; value?:number; activity?:number }, string>;
  };
  home: {
    homes: NoArgs<(Id & { name:string })[]>;
    accessories: Call<Home, HomeAccessory[]>;
    read: Call<HomeCharacteristic, HomeValue>;
    scenes: Call<Home, (Id & { name:string })[]>;
    subscribe: Call<HomeCharacteristic, string>;
    write: Call<HomeCharacteristic & { value:HomeValue }, null>;
    runScene: Call<Home & { scene:string }, null>;
  };
  security: {
    random: Call<{ length:number }, string>;
    hash: Call<{ data:string }, string>;
    setSecret: Call<{ key:string; value:string }, null>;
    getSecret: Call<{ key:string }, string | null>;
    deleteSecret: Call<{ key:string }, null>;
    encrypt: Call<{ key:string; data:string }, string>;
    decrypt: Call<{ key:string; data:string }, string>;
    biometricType: NoArgs<"none"|"faceID"|"touchID"|"other">;
    authenticate: OptionalCall<{ reason?:string }, boolean>;
  };
  system: {
    info: NoArgs<{ name:string; version:string; model:string }>;
    appearance: NoArgs<"dark"|"light">;
    battery: NoArgs<{ level:number; state:"unknown"|"unplugged"|"charging"|"full" }>;
    readClipboard: NoArgs<string | null>;
    writeClipboard: Call<{ text:string }, null>;
    share: Call<{ text:string }, boolean>;
    preview: Call<Path, null>;
    openURL: Call<{ url:string; universalOnly?:boolean }, boolean>;
    openSettings: NoArgs<boolean>;
    brightness: NoArgs<number>;
    setBrightness: Call<{ value:number }, number>;
    orientation: Call<{ value:"portrait"|"landscapeLeft"|"landscapeRight"|"automatic" }, null>;
    haptic: OptionalCall<{ style?:"light"|"medium"|"heavy"|"success"|"warning"|"error" }, null>;
  };
  network: {
    status: NoArgs<NetworkStatus>;
    watchStatus: NoArgs<string>;
    request: Call<HTTPRequest, HTTPResult>;
    download: Call<HTTPRequest & To, HTTPInfo & Path>;
    upload: Call<HTTPRequest & Path, HTTPResult>;
    openSocket: Call<Pick<HTTPRequest,'url'|'headers'|'timeout'|'progressId'>, string>;
    sendSocket: Call<Id & ({ text:string }|{ base64:string }), null>;
    closeSocket: Call<Id, null>;
  };
  graphics: {
    capabilities: NoArgs<GraphicsCapabilities>;
    showCanvas: (canvas: HTMLCanvasElement, height?: number) => Promise<Result<null>>;
    hideCanvas: () => Promise<Result<null>>;
    imageInfo: Call<Path, { width:number; height:number; frames:number; type:string }>;
    processImage: Call<Path & To & { maxDimension?:number; quality?:number; format?:"jpeg"|"png" }, string>;
    execute: Call<SQLStatement, SQLChange>;
    query: Call<SQLStatement, Record<string, SQLValue>[]>;
    transaction: Call<{ statements:SQLStatement[] }, SQLChange[]>;
  };
}

export const ios: NativeSDK;
