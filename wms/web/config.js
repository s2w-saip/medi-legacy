// HB-WMS 화면 런타임 설정 — 빌드 없이 호스트마다 바꾼다. index.html 이 먼저 읽는다.
// 쿠버네티스에서는 이 파일 하나를 ConfigMap 으로 덮어씌우면 된다(없어도 index.html 의 기본값으로 돈다).
//   mediosUrl  "AI 판단 요청" 버튼이 여는 MediOS 주소 (예: https://medios.dev.saip.io/medi)
window.WMS_CONFIG = {
  mediosUrl: 'http://10.0.20.132:8088/medi'
};
