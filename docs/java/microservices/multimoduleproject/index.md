# Multi Module Project

Creating a Multi-Module Project in IntelliJ IDEA Community Edition

Community Edition fully supports multi-module projects with **Maven** or **Gradle**. The only thing missing is the built-in Spring Initializr wizard (Ultimate only), so for Spring Boot you generate the skeleton from start.spring.io or write the POMs by hand, as shown below.

## Option 1: Maven (most common)

### Step 1: Create the parent project

1. **File → New → Project**
2. Choose **New Project** (Java), set **Build system: Maven**, pick your JDK (17 or 21)
3. Name it, for example `order-platform`, and set **GroupId** (e.g. `com.revs`)
4. Click **Create**
5. **Delete the `src` folder** in the parent. It only holds the shared build configuration.

### Step 2: Make the parent a POM

Edit the root `pom.xml`:

```xml
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.3.5</version>
        <relativePath/>
    </parent>

    <groupId>com.revs</groupId>
    <artifactId>order-platform</artifactId>
    <version>1.0.0-SNAPSHOT</version>
    <packaging>pom</packaging>          <!-- important -->

    <properties>
        <java.version>17</java.version>
    </properties>

    <modules>
        <module>common</module>
        <module>order-service</module>
        <module>payment-service</module>
    </modules>

    <!-- Versions shared by all modules, children inherit without repeating -->
    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>com.revs</groupId>
                <artifactId>common</artifactId>
                <version>${project.version}</version>
            </dependency>
        </dependencies>
    </dependencyManagement>
</project>
```

If you aren't using Spring Boot, drop the `<parent>` block and set `maven.compiler.source/target` properties instead.

### Step 3: Add child modules

1. Right-click the project root → **New → Module**
2. Choose **Maven** (Java), name it `common`
3. Confirm that **Parent** is set to `order-platform`
4. Click **Create**

IntelliJ writes the `<parent>` section into the child POM and adds the module to the parent's `<modules>` list. Repeat for `order-service` and `payment-service`.

### Step 4: Wire dependencies between modules

In `order-service/pom.xml`:

```xml
<dependencies>
    <dependency>
        <groupId>com.revs</groupId>
        <artifactId>common</artifactId>      <!-- version comes from dependencyManagement -->
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
</dependencies>

<build>
    <plugins>
        <plugin>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-maven-plugin</artifactId>
        </plugin>
    </plugins>
</build>
```

Add the Spring Boot plugin only to **runnable** modules, not to `common`, which is a plain library.

Then click the **Maven reload** icon (the "m" with a refresh arrow) in the Maven tool window.

### Resulting structure

```
order-platform/
├── pom.xml                 (packaging: pom)
├── common/
│   ├── pom.xml
│   └── src/main/java/...   (shared DTOs, events, utils)
├── order-service/
│   ├── pom.xml
│   └── src/main/java/...
└── payment-service/
    ├── pom.xml
    └── src/main/java/...
```

## Option 2: Gradle

1. **File → New → Project**, choose **Build system: Gradle**, language Java (use the **Kotlin** or **Groovy** DSL)
2. Delete the root `src` folder
3. Register modules in `settings.gradle`:

```groovy
rootProject.name = 'order-platform'
include 'common', 'order-service', 'payment-service'
```

4. Create each module as a folder with its own `build.gradle`, or use **New → Module** (Gradle)
5. Declare module dependencies:

```groovy
// order-service/build.gradle
dependencies {
    implementation project(':common')
    implementation 'org.springframework.boot:spring-boot-starter-web'
}
```

## Building and running

- **Build everything:** Maven tool window → `order-platform` → **Lifecycle → install**, or in the terminal run `mvn clean install` (`./gradlew build` for Gradle)
- **Build one module and the modules it depends on:**
  ```bash
  mvn clean install -pl order-service -am
  ```
- **Run a service:** open its `@SpringBootApplication` class and click the green run arrow. Without Ultimate's Services tool window, you can run several services at once through separate Run Configurations. Alternatively, use **Run → Edit Configurations → + → Compound** to start multiple Application configs together.

## Common problems

| Problem                                   | Fix                                                                             |
| ----------------------------------------- | ------------------------------------------------------------------------------- |
| Module not recognised as a module         | Add it under `<modules>` in the parent POM, then reload Maven                   |
| `Could not find artifact com.revs:common` | Run `mvn install` on the parent first, or build from the root with `-am`        |
| Red imports from another module           | Check the dependency is declared in the child POM, then reload Maven            |
| Wrong Java version                        | **File → Project Structure → Project SDK**, and match `java.version` in the POM |
| Child module opens as a separate project  | Use **File → Open** on the **root** `pom.xml`, not the child's                  |
| Parent has leftover `src` folder          | Delete it. A `pom`-packaging parent shouldn't have source code                  |

## Design tips

- Keep `common` small. A big shared library tightly couples your microservices, so limit it to DTOs, event contracts, and tiny utilities.
- Put all version management in the parent's `dependencyManagement` so each module doesn't pin its own versions.
- Each service module should be independently runnable and deployable, with its own `application.yml`.

If you tell me whether you prefer Maven or Gradle, I can give you a complete working example with the `common` module and two Spring Boot services that you can paste straight in.
