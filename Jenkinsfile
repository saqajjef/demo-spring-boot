pipeline {
    agent {
        docker {
            image 'maroki92/maven-jdk21-trivy:latest' // image Docker custom avec Maven 3.9 + JDK21 + Trivy
            args '-v /var/run/docker.sock:/var/run/docker.sock'
        }
    }

    environment {
        // Configuration de base
        APP_NAME = 'demo'
        DOCKER_REGISTRY = 'maroki92'  // ou votre registry
        IMAGE_NAME = "${DOCKER_REGISTRY}/${APP_NAME}"

        // Kubernetes
        KUBECONFIG = '/var/jenkins_home/.kube/config'
        K8S_NAMESPACE_DEV = 'dev'
        K8S_NAMESPACE_PROD = 'production'

        // Maven
        MAVEN_OPTS = '-Dmaven.repo.local=/var/jenkins_home/.m2/repository'
    }

    /*tools {
        maven 'Maven-3.9'  // Configurez dans Jenkins Global Tools
    }*/

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.BUILD_TAG = "${env.GIT_COMMIT}"
                }
            }
        }

        stage('Test & Build') {
            parallel {
                stage('Unit Tests') {
                    steps {
                        sh 'mvn clean test'
                    }
                    post {
                        always {
                            junit 'target/surefire-reports/*.xml'
                            //publishCoverage adapters: [jacocoAdapter('target/site/jacoco/jacoco.xml')]
                        }
                    }
                }

                stage('Code Quality') {
                    steps {
                        withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                            sh """
                                mvn sonar:sonar \
                                  -Dsonar.projectKey=${APP_NAME} \
                                  -Dsonar.host.url=http://host.docker.internal:9000 \
                                  -Dsonar.login=$SONAR_TOKEN
                            """
                        }
                    }
                }
            }
        }

        stage('Package Application') {
            steps {
                sh 'mvn clean package -DskipTests'
                archiveArtifacts artifacts: 'target/*.jar', allowEmptyArchive: false
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    def image = docker.build("${IMAGE_NAME}:${BUILD_TAG}")
                    docker.withRegistry('', 'docker-registry-credentials') {
                        image.push()
                        image.push('latest')
                    }
                }
            }
        }

        stage('Security Scan') {
            steps {
                sh 'ls -l /usr/local/share/trivy'
                sh """
                  rm -rf trivy-reports
                  mkdir -p trivy-reports

                  # Scan en JSON
                  trivy image --format json -o trivy-reports/trivy-report.json ${IMAGE_NAME}:${BUILD_TAG}

                  # Conversion en HTML avec template
                  trivy convert --format template \
                    --template /usr/local/share/trivy/html.tpl \
                    --output trivy-reports/trivy-report.html \
                    trivy-reports/trivy-report.json
                """
                archiveArtifacts artifacts: 'trivy-reports/*', allowEmptyArchive: false
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-reports/*', allowEmptyArchive: true

                    publishHTML([
                        reportDir: 'trivy-reports',
                        reportFiles: 'trivy-report.html',
                        reportName: 'Trivy Security Report',
                        keepAll: true,
                        alwaysLinkToLastBuild: true,
                        allowMissing: true
                    ])
                }
            }
        }

        stage('Update Flux Manifests') {
            steps {
                withCredentials([string(credentialsId: 'github-token', variable: 'GITHUB_TOKEN')]) {
                    script {
                        sh """
                            rm -rf flux-tmp
                            git clone https://saqajjef:${GITHUB_TOKEN}@github.com/saqajjef/flux.git flux-tmp
                            cd flux-tmp

                            echo 'Ancien tag :'
                            grep 'image:' apps/demo-spring/instance-demo-spring.yaml

                            # Mise à jour du tag
                            sed -i 's|image: .*|image: ${IMAGE_NAME}:${BUILD_TAG}|' apps/demo-spring/instance-demo-spring.yaml
                            sed -i "s|annotations:.*|annotations:\n    jenkins-build: ${BUILD_TAG}|" apps/demo-spring/instance-demo-spring.yaml

                            echo 'Nouveau tag :'
                            grep 'image:' apps/demo-spring/instance-demo-spring.yaml

                            git config user.email "jenkins@ci.local"
                            git config user.name "Jenkins CI"

                            git add apps/demo-spring/instance-demo-spring.yaml
                            git commit -m "chore: update image tag to ${IMAGE_NAME}:${BUILD_TAG}" || echo "No changes to commit"
                            git push origin main
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            // Nettoyage
            sh 'docker system prune -f'

            // Archivage des logs
            archiveArtifacts artifacts: 'target/logs/**/*.log',
                           allowEmptyArchive: true
        }

        success {
            echo "✅ Pipeline réussi pour ${env.BRANCH_NAME}"
            // Notification Slack/Teams (optionnel)
            // slackSend channel: '#deployments',
            //          message: "✅ Déploiement réussi: ${env.JOB_NAME} - ${env.BUILD_NUMBER}"
        }

        failure {
            echo "❌ Pipeline échoué pour ${env.BRANCH_NAME}"
            // Rollback automatique en cas d'échec
            script {
                if (env.BRANCH_NAME == 'main' || env.BRANCH_NAME == 'master') {
                    sh """
                        echo "Rollback automatique..."
                        kubectl rollout undo deployment/prod-spring-app -n ${K8S_NAMESPACE_PROD} || true
                    """
                }
            }
        }

        unstable {
            echo "⚠️ Pipeline instable - vérifiez les tests"
        }
    }
}