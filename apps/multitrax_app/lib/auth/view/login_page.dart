import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:formz/formz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:multitrax_app/auth/forms/login_form_cubit.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoginFormCubit(supabaseClient: Supabase.instance.client),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatelessWidget {
  const _LoginView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Multitrax Sign In')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: BlocBuilder<LoginFormCubit, LoginFormState>(
              builder: (context, state) {
                final cubit = context.read<LoginFormCubit>();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      onChanged: cubit.emailChanged,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        errorText: state.email.displayError == null
                            ? null
                            : 'Enter a valid email',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: cubit.passwordChanged,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        errorText: state.password.displayError == null
                            ? null
                            : 'Minimum 6 characters',
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: state.status == FormzSubmissionStatus.inProgress
                          ? null
                          : cubit.submit,
                      child: Text(state.isSignUp ? 'Create account' : 'Sign in'),
                    ),
                    TextButton(
                      onPressed: cubit.toggleMode,
                      child: Text(
                        state.isSignUp
                            ? 'Have an account? Sign in'
                            : 'Need an account? Sign up',
                      ),
                    ),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        state.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
