# Zeppelin 버그 조사 보고서

조사 날짜: 2025-11-16

## 요약

Apache Zeppelin 코드베이스에서 총 **21개 이상의 버그 카테고리** (100개 이상의 개별 발생)를 발견했습니다.

### 심각도별 분류
- **Critical (치명적)**: 3개 이슈
- **High (높음)**: 5개 이슈
- **Medium (중간)**: 10개 이슈
- **Low (낮음)**: 3개 이슈

---

## CRITICAL (치명적) 이슈

### 1. XSS 취약점 - eval() 사용
- **파일**: `zeppelin-web/src/app/helium/helium.service.js:287`
- **문제**: 서버로부터 받은 번들 코드를 직접 `eval()`로 실행
```javascript
eval(b);
```
- **위험**: 공격자가 번들 내용을 제어할 수 있다면 사용자 브라우저에서 임의의 JavaScript를 실행할 수 있음
- **권장 수정**: Function constructor 사용 또는 CSP(Content Security Policy) 적용, 번들 내용 검증 및 새니타이징

### 2. 명령어 인젝션 - Runtime.exec() 문자열 연결
- **파일**: `python/src/main/java/org/apache/zeppelin/python/PythonInterpreter.java:415`
- **문제**: 셸 명령어를 문자열 연결로 생성
```java
Runtime.getRuntime().exec("kill -SIGINT " + pythonPid);
```
- **위험**: pythonPid가 제어 가능하다면 명령어 인젝션 발생 가능
- **권장 수정**: ProcessBuilder를 인자 배열과 함께 사용

### 3. 명령어 인젝션 - SparkSubmitInterpreter
- **파일**: `spark-submit/src/main/java/org/apache/zeppelin/spark/submit/SparkSubmitInterpreter.java:131`
- **문제**: yarnAppId 검증 없이 명령어 실행
```java
Runtime.getRuntime().exec(new String[]{"yarn", "application", "-kill", yarnAppId});
```
- **위험**: yarnAppId 검증 없이 사용하면 인젝션 공격 가능
- **권장 수정**: yarnAppId가 예상 패턴과 일치하는지 검증

---

## HIGH (높음) 이슈

### 4. XSS 취약점 - document.write() 사용
- **파일**: `zeppelin-web/src/app/notebook/save-as/save-as.service.js:27`
- **문제**: 위험한 document.write() 사용
```javascript
frameSaveAs.document.write(content);
```
- **위험**: content가 제대로 새니타이징되지 않으면 XSS 취약점 발생
- **권장 수정**: createElement() 및 textContent 같은 안전한 DOM 조작 메서드 사용

### 5. 리소스 누수 - FileInputStream 미닫힘
- **파일**: `alluxio/src/test/java/org/apache/zeppelin/alluxio/AlluxioInterpreterTest.java:226-229`
- **문제**: FileInputStream이 예외 발생 시 닫히지 않음
```java
FileInputStream fis = new FileInputStream(testFile);
byte[] read = new byte[size];
fis.read(read);
fis.close();
```
- **위험**: read()에서 예외 발생 시 스트림이 닫히지 않아 리소스 누수
- **권장 수정**: try-with-resources 문 사용

### 6. 리소스 누수 - FileOutputStream 미닫힘
- **파일**: `flink/flink-scala-2.12/src/main/java/org/apache/zeppelin/flink/internal/JarHelper.java:119-133`
- **문제**: FileOutputStream과 BufferedOutputStream이 try-with-resources에 없음
```java
FileOutputStream fos = new FileOutputStream(destFile);
dest = new BufferedOutputStream(fos, BUFFER_SIZE);
```
- **위험**: 예외 발생 시 리소스 누수
- **권장 수정**: 모든 Closeable 리소스에 try-with-resources 사용

### 7. 리소스 누수 - BufferedReader 미닫힘
- **파일**: `python/src/main/java/org/apache/zeppelin/python/PythonCondaInterpreter.java:410-424`
- **문제**: BufferedReader 생성 후 명시적으로 닫지 않음
```java
InputStreamReader isr = new InputStreamReader(is);
BufferedReader br = new BufferedReader(isr);
```
- **위험**: StreamGobbler.run()에서 BufferedReader가 닫히지 않아 리소스 누수
- **권장 수정**: try-with-resources로 적절한 정리 보장

### 8. SQL 인젝션 방어 약함
- **파일**: `zeppelin-server/src/main/java/org/apache/zeppelin/service/ShiroAuthenticationService.java:443-456`
- **문제**: String.format()으로 동적 SQL 생성
```java
userquery = String.format("SELECT %s FROM %s WHERE %s LIKE ?", username, tablename, username);
```
- **위험**: 식별자를 정규식으로 검증하지만 SQL에 String.format 사용은 위험
- **권장 수정**: QueryBuilder 또는 ORM 프레임워크 사용

---

## MEDIUM (중간) 이슈

### 9. 잘못된 에러 처리 - printStackTrace() 프로덕션 코드
- **위치**: 여러 위치 (50개 이상 발견)
- **예시**:
  - `livy/src/test/java/org/apache/zeppelin/livy/LivyInterpreterIT.java:193`
  - `python/src/main/java/org/apache/zeppelin/python/PythonInterpreter.java:320`
  - `python/src/main/java/org/apache/zeppelin/python/PythonCondaInterpreter.java:423`
- **문제**: 적절한 로깅 대신 printStackTrace() 사용
- **위험**: 민감한 정보 노출 가능, 설정 불가능
- **권장 수정**: 예외 파라미터와 함께 logger.error() 사용

### 10. 더 이상 사용되지 않는 API 사용
- **파일**: `zeppelin-interpreter/src/main/java/org/apache/zeppelin/interpreter/ZeppelinContext.java`
- **라인**: 다수 (69, 74, 83, 93, 220, 249, 310, 350, 658, 688, 714, 736, 759, 780, 801)
- **문제**: 여러 @Deprecated 메서드가 여전히 사용 중
- **권장 수정**: 더 이상 사용되지 않는 API를 새로운 대안으로 교체

### 11. 확인되지 않은 타입 캐스트
- **위치**: @SuppressWarnings("unchecked")가 있는 여러 위치
- **예시**:
  - `groovy/src/main/java/org/apache/zeppelin/groovy/GroovyInterpreter.java:123`
  - `zeppelin-zengine/src/main/java/org/apache/zeppelin/util/ReflectionUtils.java:74`
- **문제**: @SuppressWarnings로 타입 안전성 우회
- **권장 수정**: 적절한 제네릭 사용 또는 런타임에 타입 검증

### 12. 테스트의 Thread.sleep (취약한 테스트)
- **위치**: 여러 테스트 파일
- **예시**:
  - `python/src/test/java/org/apache/zeppelin/python/PythonInterpreterTest.java:116`
  - `python/src/test/java/org/apache/zeppelin/python/BasePythonInterpreterTest.java` (여러 인스턴스)
- **문제**: 하드코딩된 Thread.sleep()
- **위험**: 느린 시스템에서 불안정한 테스트 발생
- **권장 수정**: 타임아웃이 있는 적절한 대기 메커니즘 사용 (Awaitility 라이브러리 등)

### 13. NullPointerException 가능성 - Null 체크 누락
- **파일**: `jdbc/src/main/java/org/apache/zeppelin/jdbc/JDBCInterpreter.java`
- **라인**: 다수 (191, 408, 535, 538, 673 등)
- **문제**: 명확한 문서 없이 null을 반환하는 메서드
- **권장 수정**: Optional<T> 사용 또는 모든 호출 지점에서 null 체크 보장

### 14. 프로덕션 코드의 콘솔 출력
- **파일**: `alluxio/src/main/java/org/apache/zeppelin/alluxio/AlluxioInterpreter.java`
- **라인**: 130, 140
- **문제**: 프로덕션 코드에서 System.out.println() 사용
```java
System.out.println(getCommandList());
```
- **권장 수정**: logger.info() 또는 적절한 로그 레벨로 교체

### 15. TODO 주석 (미완성 작업)
- **위치**: 여러 위치
- **예시**:
  - `zeppelin-web-angular/src/app/pages/workspace/notebook/action-bar/action-bar.component.ts:240-249` - 미구현 검색 기능
  - `flink/flink-scala-2.12/src/test/java/org/apache/zeppelin/flink/FlinkSqlInterpreterTest.java:607` - CSV Sink 버그 관련 TODO
- **문제**: TODO 주석은 기능이 미완성임을 나타냄
- **권장 수정**: 구현 완료 또는 적절한 이슈 트래킹 티켓 생성

### 16. 약한 난수 생성
- **파일**: `neo4j/src/main/java/org/apache/zeppelin/graph/neo4j/utils/Neo4jConversionUtils.java:84`
- **문제**: 색상 생성에 Math.random() 사용
```java
color[i] = LETTERS[(int) Math.floor(Math.random() * 16)].charAt(0);
```
- **권장 수정**: UI 목적임을 문서화하거나 더 나은 성능을 위해 ThreadLocalRandom 사용

### 17. 에러 체크 없는 파일 삭제
- **파일**: `flink/flink-scala-2.12/src/test/java/org/apache/zeppelin/flink/FlinkSqlInterpreterTest.java:622`
- **문제**: File.delete() 결과를 체크하지 않음
```java
file.delete();
```
- **권장 수정**: 반환값 체크 또는 Files.deleteIfExists() 사용 및 예외 처리

### 18. 잠재적 경쟁 조건 - 적절한 동기화 없는 notify()
- **파일**: `python/src/main/java/org/apache/zeppelin/python/PythonInterpreter.java`
- **라인**: 335, 364, 467, 621, 629, 637
- **문제**: notify() 호출되지만 동기화 컨텍스트 불명확
- **권장 수정**: 동기화 전략 검토 및 상위 수준 동시성 유틸리티 사용

---

## LOW (낮음) 이슈

### 19. 빈 Catch 블록
- **파일**: `livy/src/test/java/org/apache/zeppelin/livy/LivyInterpreterIT.java:359-367`
- **문제**: 예외를 무시하는 이유를 설명하는 주석만 있는 catch 블록
- **권장 수정**: 테스트에서 특정 예상 예외 사용 고려 또는 최소한 디버그 레벨로 로깅

### 20. 긴 메서드 - 여러 책임
- **파일**: `jdbc/src/main/java/org/apache/zeppelin/jdbc/JDBCInterpreter.java`
- **문제**: 여러 책임을 가진 매우 긴 메서드 (~800+ 라인)
- **권장 수정**: 단일 책임을 가진 더 작은 메서드로 리팩터링

### 21. 매직 넘버
- **위치**: 여러 파일의 하드코딩된 타임아웃 값
- **예시**: `Thread.sleep(3000)`, `Thread.sleep(5000)` 등
- **문제**: 설명 없이 하드코딩된 숫자
- **권장 수정**: 명확한 목적을 가진 명명된 상수로 추출

---

## 우선순위 수정 권장사항

1. **즉시 수정** (Critical):
   - XSS 취약점 수정
   - 명령어 인젝션 이슈 수정

2. **조속히 수정** (High):
   - try-with-resources로 모든 리소스 누수 해결
   - SQL 쿼리 빌더 개선

3. **중기 수정** (Medium):
   - printStackTrace를 적절한 로깅으로 교체
   - 포괄적인 null 체크 추가 또는 Optional 사용
   - 프로덕션 코드에서 System.out.println 제거

4. **장기 수정** (Low):
   - 모든 TODO 항목에 대한 티켓 생성 및 완료 또는 제거
   - 긴 메서드 리팩터링
   - 매직 넘버를 명명된 상수로 교체

---

## 적용된 수정사항

다음 수정사항들이 이 조사의 일환으로 적용되었습니다:

### 1. FileInputStream 리소스 누수 수정
- **파일**: `alluxio/src/test/java/org/apache/zeppelin/alluxio/AlluxioInterpreterTest.java`
- **변경**: try-with-resources로 변경하여 스트림이 항상 닫히도록 함

### 2. FileOutputStream 리소스 누수 수정
- **파일**: `flink/flink-scala-2.12/src/main/java/org/apache/zeppelin/flink/internal/JarHelper.java`
- **변경**: try-with-resources로 변경하여 모든 스트림이 적절히 닫히도록 함

### 3. BufferedReader 리소스 누수 수정
- **파일**: `python/src/main/java/org/apache/zeppelin/python/PythonCondaInterpreter.java`
- **변경**: try-with-resources로 변경하여 reader가 항상 닫히도록 함

### 4. 명령어 인젝션 방어 강화
- **파일**: `python/src/main/java/org/apache/zeppelin/python/PythonInterpreter.java`
- **변경**: pythonPid 검증 추가 및 ProcessBuilder 사용

### 5. Yarn Application ID 검증 추가
- **파일**: `spark-submit/src/main/java/org/apache/zeppelin/spark/submit/SparkSubmitInterpreter.java`
- **변경**: yarnAppId 형식 검증 추가

### 6. 프로덕션 콘솔 출력을 로깅으로 교체
- **파일**: `alluxio/src/main/java/org/apache/zeppelin/alluxio/AlluxioInterpreter.java`
- **변경**: System.out.println()을 logger.info()로 교체

### 7. File.delete() 반환값 체크
- **파일**: `flink/flink-scala-2.12/src/test/java/org/apache/zeppelin/flink/FlinkSqlInterpreterTest.java`
- **변경**: 삭제 실패 시 경고 로그 추가

---

## 결론

이 조사는 Apache Zeppelin 코드베이스에서 여러 심각도의 다양한 버그와 코드 품질 문제를 발견했습니다. 가장 중요한 보안 취약점(XSS, 명령어 인젝션)과 리소스 관리 문제는 즉시 해결이 필요합니다.

일부 HIGH 및 MEDIUM 우선순위 버그들은 이 조사의 일환으로 수정되었으며, 나머지 이슈들은 적절한 우선순위에 따라 해결되어야 합니다.
