# 메모리 및 리소스 누수 분석 보고서 (Resource Leak Analysis Report)

생성일: 2025-11-16

## 개요 (Overview)

Apache Zeppelin 코드베이스에서 발견된 메모리 및 리소스 누수 패턴에 대한 종합 분석입니다.

## 주요 발견 사항 (Key Findings)

### 1. 닫히지 않은 파일 스트림 (Unclosed File Streams)

#### 🔴 높은 우선순위 (High Priority)

#### 1.1 FileReader 누수

**파일:** `zeppelin-interpreter-integration/src/test/java/org/apache/zeppelin/integration/SparkIntegrationTest.java:151`
```java
// 문제: FileReader가 닫히지 않음
MavenXpp3Reader reader = new MavenXpp3Reader();
Model model = reader.read(new FileReader("pom.xml"));
```
- **문제점:** FileReader가 열렸지만 닫히지 않음. try-with-resources나 finally 블록 없음
- **영향:** 파일 핸들 누수, 시스템 리소스 고갈 가능
- **해결방안:** try-with-resources 사용

**파일:** `zeppelin-zengine/src/main/java/org/apache/zeppelin/helium/HeliumBundleFactory.java:308`
```java
// 문제: JsonReader/FileReader 명시적으로 닫히지 않음
JsonReader reader = new JsonReader(new FileReader(existingPackageJson));
Map<String, Object> packageJson = gson.fromJson(reader,
    new TypeToken<Map<String, Object>>(){}.getType());
```
- **문제점:** Gson이 닫을 수 있지만, 명시적 닫기가 더 안전
- **해결방안:** try-with-resources로 명시적 관리

**파일:** `zeppelin-zengine/src/main/java/org/apache/zeppelin/helium/HeliumOnlineRegistry.java:164`
```java
// 문제: FileReader 닫히지 않음
return gson.fromJson(
    new FileReader(registryCacheFile),
    new TypeToken<List<HeliumPackage>>() {}.getType());
```
- **문제점:** FileReader가 try-with-resources나 finally에서 닫히지 않음
- **해결방안:** try-with-resources 패턴 적용

#### 1.2 FileInputStream/FileOutputStream 누수

**파일:** `flink/flink-scala-2.12/src/main/java/org/apache/zeppelin/flink/internal/JarHelper.java:93,119,177`

**Line 93:**
```java
public void unjarDir(File jarFile, File destDir) throws IOException {
    FileInputStream fis = new FileInputStream(jarFile);
    unjar(fis, destDir);  // fis가 여기서 닫히지 않음
}
```
- **문제점:** 93라인의 FileInputStream이 unjar()에 전달되지만, 예외 발생 시 닫힘이 보장되지 않음
- **심각도:** HIGH

**Line 119:**
```java
FileOutputStream fos = new FileOutputStream(destFile);
dest = new BufferedOutputStream(fos, BUFFER_SIZE);
// finally에서 dest.close() 있지만 unchecked exception 발생 시 누수 가능
```

**Line 177:**
```java
FileInputStream fis = new FileInputStream(dirOrFile2jar);
// 93라인과 유사한 패턴
```

### 2. 닫히지 않은 BufferedReader/BufferedWriter (Unclosed Buffered Streams)

#### 🔴 높은 우선순위 (High Priority)

**파일:** `zeppelin-integration/src/test/java/org/apache/zeppelin/ProcessData.java:168-169`
```java
InputStream in = this.checked_process.getInputStream();
InputStream inErrors = this.checked_process.getErrorStream();
BufferedReader inReader = new BufferedReader(new InputStreamReader(in));
BufferedReader inReaderErrors = new BufferedReader(new InputStreamReader(inErrors));
// ... while 루프에서 사용되지만 명시적으로 닫히지 않음
```
- **문제점:** BufferedReader와 InputStreamReader가 닫히지 않음
- **영향:** 프로세스 스트림 누수
- **심각도:** HIGH

**파일:** `python/src/main/java/org/apache/zeppelin/python/PythonCondaInterpreter.java:410-411`
```java
InputStreamReader isr = new InputStreamReader(is);
BufferedReader br = new BufferedReader(isr);
String line = null;
while ((line = br.readLine()) != null) {
    output.append(line + "\n");
}
// close() 호출 없음 - 누수!
```
- **문제점:** InputStreamReader와 BufferedReader 모두 닫히지 않음
- **심각도:** HIGH

**파일:** `python/src/main/java/org/apache/zeppelin/python/PythonDockerInterpreter.java:182`
```java
InputStream stdout = process.getInputStream();
BufferedReader br = new BufferedReader(new InputStreamReader(stdout));
String line;
while ((line = br.readLine()) != null) {
    out.write(line + "\n");
}
// close() 없음 - 누수!
```
- **문제점:** BufferedReader와 InputStreamReader 닫히지 않음
- **심각도:** HIGH

**파일:** `shell/terminal/service/TerminalService.java:79-81`
```java
this.inputReader = new BufferedReader(new InputStreamReader(process.getInputStream()));
this.errorReader = new BufferedReader(new InputStreamReader(process.getErrorStream()));
this.outputWriter = new BufferedWriter(new OutputStreamWriter(process.getOutputStream()));
```
- **문제점:** 인스턴스 필드로 저장되며, 프로세스가 교체/종료될 때 이전 스트림이 닫히지 않을 수 있음
- **심각도:** MEDIUM

### 3. ExecutorService 미종료 (ExecutorService Not Properly Shutdown)

#### 🟡 중간 우선순위 (Medium Priority)

**파일:** `zeppelin-server/src/main/java/org/apache/zeppelin/socket/NotebookServer.java:147`
```java
private final ExecutorService executorService = Executors.newFixedThreadPool(10);
```
- **문제점:** `shutdown()` 또는 `shutdownNow()` 호출이 보이지 않음
- **영향:** 스레드 누수, JVM 종료 지연
- **확인 필요:** close 메서드에서 shutdown 호출 여부 확인

**파일:** `flink/flink-scala-2.12/src/main/java/org/apache/zeppelin/flink/sql/AbstractStreamSqlJob.java:72`
```java
protected ScheduledExecutorService refreshScheduler = Executors.newScheduledThreadPool(1);
```
- **문제점:** cleanup/close 메서드에서 제대로 종료되는지 확인 필요
- **심각도:** MEDIUM

### 4. 무제한 증가 가능한 정적 컬렉션 (Static Collections with Unbounded Growth)

#### 🟡 중간 우선순위 (Medium Priority)

**파일:** `rlang/src/main/java/org/apache/zeppelin/r/ZeppelinR.java:45`
```java
static Map<Integer, ZeppelinR> zeppelinR = Collections.synchronizedMap(new HashMap());
```
- **문제점:** 크기 제한이나 제거 정책이 없는 HashMap
- **영향:** 시간이 지남에 따라 ZeppelinR 인스턴스가 무한정 누적될 수 있음
- **해결방안:** LRUCache 사용 또는 명시적 정리 메커니즘 추가
- **심각도:** MEDIUM

### 5. 올바른 패턴 (Good Patterns)

#### ✅ LRU 캐시 사용 (좋은 사례)

**파일:** `zeppelin-notebook/src/main/java/org/apache/zeppelin/notebook/NoteManager.java:708`
```java
this.lruCache = Metrics.gaugeMapSize("zeppelin_note_cache", Tags.empty(),
    Collections.synchronizedMap(new LRUCache()));
```
- **장점:** 크기 관리를 위한 LRUCache 사용

#### ✅ WeakHashMap 사용 (좋은 사례)

**파일:** `groovy/src/main/java/org/apache/zeppelin/groovy/GroovyInterpreter.java:60`
```java
.synchronizedMap(new WeakHashMap<String, Class<Script>>(100));
```
- **장점:** 항목의 자동 가비지 컬렉션을 위한 WeakHashMap 사용

#### ✅ JDBC 리소스 정리 (좋은 사례)

**파일:** `zeppelin-server/src/main/java/org/apache/zeppelin/service/ShiroAuthenticationService.java:463-477`
```java
try {
    con = dataSource.getConnection();
    ps = con.prepareStatement(userquery);
    ps.setString(1, "%" + searchText + "%");
    rs = ps.executeQuery();
    // ... 사용
} catch (Exception e) {
    LOGGER.error("Error retrieving User list from JDBC Realm", e);
} finally {
    JdbcUtils.closeResultSet(rs);
    JdbcUtils.closeStatement(ps);
    JdbcUtils.closeConnection(con);
}
```
- **장점:** finally 블록에서 JdbcUtils로 정리
- **개선 가능:** Java 7+ try-with-resources 사용

## 요약 테이블 (Summary Table)

| 파일 | 라인 | 유형 | 심각도 | 문제 |
|------|------|------|---------|------|
| SparkIntegrationTest.java | 151 | FileReader | 🔴 HIGH | 닫히지 않음 |
| HeliumBundleFactory.java | 308 | JsonReader/FileReader | 🔴 HIGH | 명시적으로 닫히지 않음 |
| HeliumOnlineRegistry.java | 164 | FileReader | 🔴 HIGH | 닫히지 않음 |
| JarHelper.java | 93, 119, 177 | FileInputStream/OutputStream | 🔴 HIGH | 예외 시 누수 가능 |
| ProcessData.java | 168-169 | BufferedReader | 🔴 HIGH | 닫히지 않음 |
| PythonCondaInterpreter.java | 410-411 | BufferedReader | 🔴 HIGH | 닫히지 않음 |
| PythonDockerInterpreter.java | 182 | BufferedReader | 🔴 HIGH | 닫히지 않음 |
| TerminalService.java | 79-81 | BufferedReader/Writer | 🟡 MEDIUM | 교체 시 누수 가능 |
| ZeppelinR.java | 45 | Static HashMap | 🟡 MEDIUM | 무제한 증가 |
| NotebookServer.java | 147 | ExecutorService | 🟡 MEDIUM | shutdown 확인 필요 |
| AbstractStreamSqlJob.java | 72 | ScheduledExecutorService | 🟡 MEDIUM | shutdown 확인 필요 |

## 권장 사항 (Recommendations)

### 1. Try-with-resources로 전환 ⭐⭐⭐
- **대상:** 모든 `FileInputStream`, `FileOutputStream`, `FileReader`, `FileWriter`, `BufferedReader`, `BufferedWriter`
- **이유:** 자동 리소스 관리, 예외 발생 시에도 닫힘 보장
- **예제:**
```java
// Before (나쁜 예)
FileReader reader = new FileReader("file.txt");
// ... 사용
reader.close();

// After (좋은 예)
try (FileReader reader = new FileReader("file.txt")) {
    // ... 사용
} // 자동으로 닫힘
```

### 2. BufferedReader/Writer 명시적 닫기 ⭐⭐⭐
- **대상:** `ProcessData.java`, `PythonCondaInterpreter.java`, `PythonDockerInterpreter.java`
- **해결방안:**
```java
try (BufferedReader br = new BufferedReader(new InputStreamReader(is))) {
    String line;
    while ((line = br.readLine()) != null) {
        output.append(line).append("\n");
    }
}
```

### 3. ExecutorService Shutdown Hook 추가 ⭐⭐
- **대상:** `NotebookServer.java`, `AbstractStreamSqlJob.java`
- **확인 필요:** close() 또는 cleanup() 메서드 존재 여부
- **해결방안:**
```java
@Override
public void close() {
    executorService.shutdown();
    try {
        if (!executorService.awaitTermination(60, TimeUnit.SECONDS)) {
            executorService.shutdownNow();
        }
    } catch (InterruptedException e) {
        executorService.shutdownNow();
        Thread.currentThread().interrupt();
    }
}
```

### 4. 정적 컬렉션에 크기 제한 구현 ⭐⭐
- **대상:** `ZeppelinR.java:45`
- **해결방안:**
  - LRUCache 사용 (NoteManager.java 참고)
  - WeakHashMap 사용 (GroovyInterpreter.java 참고)
  - 명시적 제거 정책 추가

### 5. 단위 테스트 추가 ⭐
- **목적:** 리소스가 제대로 닫히는지 검증
- **도구:** Mockito, PowerMock, 또는 실제 리소스 모니터링

## 우선순위 수정 계획 (Prioritized Fix Plan)

### Phase 1: 긴급 (Immediate - High Priority)
1. ✅ `SparkIntegrationTest.java:151` - FileReader 닫기
2. ✅ `HeliumBundleFactory.java:308` - JsonReader/FileReader 닫기
3. ✅ `HeliumOnlineRegistry.java:164` - FileReader 닫기
4. ✅ `JarHelper.java:93,119,177` - FileInputStream/OutputStream 관리
5. ✅ `ProcessData.java:168-169` - BufferedReader 닫기
6. ✅ `PythonCondaInterpreter.java:410-411` - BufferedReader 닫기
7. ✅ `PythonDockerInterpreter.java:182` - BufferedReader 닫기

### Phase 2: 중요 (Important - Medium Priority)
1. ⏳ `TerminalService.java:79-81` - 스트림 생명주기 관리
2. ⏳ `NotebookServer.java:147` - ExecutorService shutdown 확인/추가
3. ⏳ `AbstractStreamSqlJob.java:72` - ScheduledExecutorService shutdown 확인/추가
4. ⏳ `ZeppelinR.java:45` - 정적 Map에 크기 제한 추가

### Phase 3: 개선 (Enhancement)
1. 📝 Try-finally 패턴을 try-with-resources로 전환
2. 📝 리소스 정리에 대한 단위 테스트 추가
3. 📝 코드 리뷰 체크리스트에 리소스 관리 항목 추가

## 참고 자료 (References)

- [Oracle: The try-with-resources Statement](https://docs.oracle.com/javase/tutorial/essential/exceptions/tryResourceClose.html)
- [Effective Java, 3rd Edition - Item 9: Prefer try-with-resources to try-finally](https://www.oreilly.com/library/view/effective-java-3rd/9780134686097/)
- [Java Concurrency in Practice - Thread Pool Shutdown](http://jcip.net/)

## 다음 단계 (Next Steps)

1. ✅ 이 보고서를 팀과 공유
2. ⏳ Phase 1 수정 사항에 대한 JIRA 티켓 생성
3. ⏳ 코드 리뷰 가이드라인에 리소스 관리 체크리스트 추가
4. ⏳ 정적 분석 도구(SpotBugs, ErrorProne) 설정하여 향후 누수 방지
5. ⏳ CI/CD 파이프라인에 리소스 누수 검사 통합

---

**작성자:** Claude Code Agent
**검토 필요:** Apache Zeppelin 개발팀
**마지막 업데이트:** 2025-11-16
